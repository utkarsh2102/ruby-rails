# frozen_string_literal: true

require "isolation/abstract_unit"
require "env_helpers"

module ApplicationTests
  module RakeTests
    class RakeDbsTest < ActiveSupport::TestCase
      include ActiveSupport::Testing::Isolation, EnvHelpers

      def setup
        build_app
        FileUtils.rm_rf("#{app_path}/config/environments")
      end

      def teardown
        teardown_app
      end

      def database_url_db_name
        "db/database_url_db.sqlite3"
      end

      def set_database_url
        ENV["DATABASE_URL"] = "sqlite3:#{database_url_db_name}"
        # ensure it's using the DATABASE_URL
        FileUtils.rm_rf("#{app_path}/config/database.yml")
      end

      def db_create_and_drop(expected_database, environment_loaded: true)
        Dir.chdir(app_path) do
          output = rails("db:create")
          assert_match(/Created database/, output)
          assert File.exist?(expected_database)
          yield if block_given?
          assert_equal expected_database, ActiveRecord::Base.connection_config[:database] if environment_loaded
          output = rails("db:drop")
          assert_match(/Dropped database/, output)
          assert_not File.exist?(expected_database)
        end
      end

      def db_create_with_warning(expected_database)
        Dir.chdir(app_path) do
          output = rails("db:create")
          assert_match(/Rails couldn't infer whether you are using multiple databases/, output)
          assert_match(/Created database/, output)
          assert File.exist?(expected_database)
        end
      end

      test "db:create and db:drop without database URL" do
        require "#{app_path}/config/environment"
        db_create_and_drop ActiveRecord::Base.configurations[Rails.env]["database"]
      end

      test "db:create and db:drop with database URL" do
        require "#{app_path}/config/environment"
        set_database_url
        db_create_and_drop database_url_db_name
      end

      test "db:create and db:drop respect environment setting" do
        app_file "config/database.yml", <<-YAML
          <% 1 %>
          development:
            database: <%= Rails.application.config.database %>
            adapter: sqlite3
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_and_drop("db/development.sqlite3", environment_loaded: false)
      end

      test "db:create and db:drop don't raise errors when loading YAML with multiline ERB" do
        app_file "config/database.yml", <<-YAML
          development:
            database: <%=
              Rails.application.config.database
            %>
            adapter: sqlite3
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_and_drop("db/development.sqlite3", environment_loaded: false)
      end

      test "db:create and db:drop show warning but doesn't raise errors when loading YAML with alias ERB" do
        app_file "config/database.yml", <<-YAML
          sqlite: &sqlite
            adapter: sqlite3
            database: db/development.sqlite3

          development:
            <<: *<%= ENV["DB"] || "sqlite" %>
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_with_warning("db/development.sqlite3")
      end

      test "db:create and db:drop don't raise errors when loading YAML containing conditional statements in ERB" do
        app_file "config/database.yml", <<-YAML
          development:
          <% if Rails.application.config.database %>
            database: <%= Rails.application.config.database %>
          <% else %>
            database: db/default.sqlite3
          <% end %>
            adapter: sqlite3
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_and_drop("db/development.sqlite3", environment_loaded: false)
      end

      test "db:create and db:drop don't raise errors when loading YAML containing multiple ERB statements on the same line" do
        app_file "config/database.yml", <<-YAML
          development:
            database: <% if Rails.application.config.database %><%= Rails.application.config.database %><% else %>db/default.sqlite3<% end %>
            adapter: sqlite3
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_and_drop("db/development.sqlite3", environment_loaded: false)
      end

      test "db:create and db:drop dont raise errors when loading YAML with FIXME ERB" do
        app_file "config/database.yml", <<-YAML
          development:
            <%= Rails.application.config.database ? 'database: db/development.sqlite3' : 'database: db/development.sqlite3' %>
            adapter: sqlite3
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_and_drop("db/development.sqlite3", environment_loaded: false)
      end

      test "db:create and db:drop don't raise errors when loading YAML which contains a key's value as an ERB statement" do
        app_file "config/database.yml", <<-YAML
          development:
            database: <%= Rails.application.config.database ? 'db/development.sqlite3' : 'db/development.sqlite3' %>
            custom_option: <%= ENV['CUSTOM_OPTION'] %>
            adapter: sqlite3
        YAML

        app_file "config/environments/development.rb", <<-RUBY
          Rails.application.configure do
            config.database = "db/development.sqlite3"
          end
        RUBY

        db_create_and_drop("db/development.sqlite3", environment_loaded: false)
      end

      def with_database_existing
        Dir.chdir(app_path) do
          set_database_url
          rails "db:create"
          yield
          rails "db:drop"
        end
      end

      test "db:create failure because database exists" do
        with_database_existing do
          output = rails("db:create")
          assert_match(/already exists/, output)
        end
      end

      def with_bad_permissions
        Dir.chdir(app_path) do
          skip "Can't avoid permissions as root" if Process.uid.zero?

          set_database_url
          FileUtils.chmod("-w", "db")
          yield
          FileUtils.chmod("+w", "db")
        end
      end

      test "db:create failure because bad permissions" do
        with_bad_permissions do
          output = rails("db:create", allow_failure: true)
          assert_match("Couldn't create '#{database_url_db_name}' database. Please check your configuration.", output)
          assert_equal 1, $?.exitstatus
        end
      end

      test "db:create works when schema cache exists and database does not exist" do
        use_postgresql

        begin
          rails %w(db:create db:migrate db:schema:cache:dump)

          rails "db:drop"
          rails "db:create"
          assert_equal 0, $?.exitstatus
        ensure
          rails "db:drop" rescue nil
        end
      end

      test "db:drop failure because database does not exist" do
        output = rails("db:drop:_unsafe", "--trace")
        assert_match(/does not exist/, output)
      end

      test "db:drop failure because bad permissions" do
        with_database_existing do
          with_bad_permissions do
            output = rails("db:drop", allow_failure: true)
            assert_match(/Couldn't drop/, output)
            assert_equal 1, $?.exitstatus
          end
        end
      end

      test "db:truncate_all truncates all non-internal tables" do
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          rails "db:migrate"
          require "#{app_path}/config/environment"
          Book.create!(title: "Remote")
          assert_equal 1, Book.count
          schema_migrations = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
          internal_metadata = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")

          rails "db:truncate_all"

          assert_equal(
            schema_migrations,
            ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
          )
          assert_equal(
            internal_metadata,
            ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")
          )
          assert_equal 0, Book.count
        end
      end

      test "db:truncate_all does not truncate any tables when environment is protected" do
        with_rails_env "production" do
          Dir.chdir(app_path) do
            rails "generate", "model", "book", "title:string"
            rails "db:migrate"
            require "#{app_path}/config/environment"
            Book.create!(title: "Remote")
            assert_equal 1, Book.count
            schema_migrations = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
            internal_metadata = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")
            books = ActiveRecord::Base.connection.execute("SELECT * from \"books\"")

            output = rails("db:truncate_all", allow_failure: true)
            assert_match(/ActiveRecord::ProtectedEnvironmentError/, output)

            assert_equal(
              schema_migrations,
              ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
            )
            assert_equal(
              internal_metadata,
              ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")
            )
            assert_equal 1, Book.count
            assert_equal(books, ActiveRecord::Base.connection.execute("SELECT * from \"books\""))
          end
        end
      end

      def db_migrate_and_status(expected_database)
        rails "generate", "model", "book", "title:string"
        rails "db:migrate"
        output = rails("db:migrate:status")
        assert_match(%r{database:\s+\S*#{Regexp.escape(expected_database)}}, output)
        assert_match(/up\s+\d{14}\s+Create books/, output)
      end

      test "db:migrate and db:migrate:status without database_url" do
        require "#{app_path}/config/environment"
        db_migrate_and_status ActiveRecord::Base.configurations[Rails.env]["database"]
      end

      test "db:migrate and db:migrate:status with database_url" do
        require "#{app_path}/config/environment"
        set_database_url
        db_migrate_and_status database_url_db_name
      end

      def db_schema_dump
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          rails "db:migrate", "db:schema:dump"
          schema_dump = File.read("db/schema.rb")
          assert_match(/create_table \"books\"/, schema_dump)
        end
      end

      test "db:schema:dump without database_url" do
        db_schema_dump
      end

      test "db:schema:dump with database_url" do
        set_database_url
        db_schema_dump
      end

      def db_fixtures_load(expected_database)
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          reload
          rails "db:migrate", "db:fixtures:load"

          assert_match expected_database, ActiveRecord::Base.connection_config[:database]
          assert_equal 2, Book.count
        end
      end

      test "db:fixtures:load without database_url" do
        require "#{app_path}/config/environment"
        db_fixtures_load ActiveRecord::Base.configurations[Rails.env]["database"]
      end

      test "db:fixtures:load with database_url" do
        require "#{app_path}/config/environment"
        set_database_url
        db_fixtures_load database_url_db_name
      end

      test "db:fixtures:load with namespaced fixture" do
        require "#{app_path}/config/environment"

        rails "generate", "model", "admin::book", "title:string"
        reload
        rails "db:migrate", "db:fixtures:load"

        assert_equal 2, Admin::Book.count
      end

      def db_structure_dump_and_load(expected_database)
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          rails "db:migrate", "db:structure:dump"
          structure_dump = File.read("db/structure.sql")
          assert_match(/CREATE TABLE (?:IF NOT EXISTS )?\"books\"/, structure_dump)
          rails "environment", "db:drop", "db:structure:load"
          assert_match expected_database, ActiveRecord::Base.connection_config[:database]
          require "#{app_path}/app/models/book"
          # if structure is not loaded correctly, exception would be raised
          assert_equal 0, Book.count
        end
      end

      test "db:structure:dump and db:structure:load without database_url" do
        require "#{app_path}/config/environment"
        db_structure_dump_and_load ActiveRecord::Base.configurations[Rails.env]["database"]
      end

      test "db:structure:dump and db:structure:load with database_url" do
        require "#{app_path}/config/environment"
        set_database_url
        db_structure_dump_and_load database_url_db_name
      end

      test "db:structure:dump and db:structure:load set ar_internal_metadata" do
        require "#{app_path}/config/environment"
        db_structure_dump_and_load ActiveRecord::Base.configurations[Rails.env]["database"]

        assert_equal "test", rails("runner", "-e", "test", "puts ActiveRecord::InternalMetadata[:environment]").strip
        assert_equal "development", rails("runner", "puts ActiveRecord::InternalMetadata[:environment]").strip
      end

      test "db:structure:dump does not dump schema information when no migrations are used" do
        # create table without migrations
        rails "runner", "ActiveRecord::Base.connection.create_table(:posts) {|t| t.string :title }"

        stderr_output = capture(:stderr) { rails("db:structure:dump", stderr: true, allow_failure: true) }
        assert_empty stderr_output
        structure_dump = File.read("#{app_path}/db/structure.sql")
        assert_match(/CREATE TABLE (?:IF NOT EXISTS )?\"posts\"/, structure_dump)
      end

      test "db:schema:load and db:structure:load do not purge the existing database" do
        rails "runner", "ActiveRecord::Base.connection.create_table(:posts) {|t| t.string :title }"

        app_file "db/schema.rb", <<-RUBY
          ActiveRecord::Schema.define(version: 20140423102712) do
            create_table(:comments) {}
          end
        RUBY

        list_tables = lambda { rails("runner", "p ActiveRecord::Base.connection.tables").strip }

        assert_equal '["posts"]', list_tables[]
        rails "db:schema:load"
        assert_equal '["posts", "comments", "schema_migrations", "ar_internal_metadata"]', list_tables[]

        app_file "db/structure.sql", <<-SQL
          CREATE TABLE "users" ("id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar(255));
        SQL

        rails "db:structure:load"
        assert_equal '["posts", "comments", "schema_migrations", "ar_internal_metadata", "users"]', list_tables[]
      end

      test "db:schema:load with inflections" do
        app_file "config/initializers/inflection.rb", <<-RUBY
          ActiveSupport::Inflector.inflections do |inflect|
            inflect.irregular 'goose', 'geese'
          end
        RUBY
        app_file "config/initializers/primary_key_table_name.rb", <<-RUBY
          ActiveRecord::Base.primary_key_prefix_type = :table_name
        RUBY
        app_file "db/schema.rb", <<-RUBY
          ActiveRecord::Schema.define(version: 20140423102712) do
            create_table("goose".pluralize) do |t|
              t.string :name
            end
          end
        RUBY

        rails "db:schema:load"

        tables = rails("runner", "p ActiveRecord::Base.connection.tables").strip
        assert_match(/"geese"/, tables)

        columns = rails("runner", "p ActiveRecord::Base.connection.columns('geese').map(&:name)").strip
        assert_equal columns, '["gooseid", "name"]'
      end

      test "db:schema:load fails if schema.rb doesn't exist yet" do
        stderr_output = capture(:stderr) { rails("db:schema:load", stderr: true, allow_failure: true) }
        assert_match(/Run `rails db:migrate` to create it/, stderr_output)
      end

      def db_test_load_structure
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          rails "db:migrate", "db:structure:dump", "db:test:load_structure"
          ActiveRecord::Base.configurations = Rails.application.config.database_configuration
          ActiveRecord::Base.establish_connection :test
          require "#{app_path}/app/models/book"
          # if structure is not loaded correctly, exception would be raised
          assert_equal 0, Book.count
          assert_match ActiveRecord::Base.configurations["test"]["database"],
            ActiveRecord::Base.connection_config[:database]
        end
      end

      test "db:test:load_structure without database_url" do
        require "#{app_path}/config/environment"
        db_test_load_structure
      end

      test "db:setup loads schema and seeds database" do
        @old_rails_env = ENV["RAILS_ENV"]
        @old_rack_env = ENV["RACK_ENV"]
        ENV.delete "RAILS_ENV"
        ENV.delete "RACK_ENV"

        app_file "db/schema.rb", <<-RUBY
            ActiveRecord::Schema.define(version: "1") do
              create_table :users do |t|
                t.string :name
              end
            end
          RUBY

        app_file "db/seeds.rb", <<-RUBY
          puts ActiveRecord::Base.connection_config[:database]
        RUBY

        database_path = rails("db:setup")
        assert_equal "development.sqlite3", File.basename(database_path.strip)
      ensure
        ENV["RAILS_ENV"] = @old_rails_env
        ENV["RACK_ENV"] = @old_rack_env
      end

      test "db:setup sets ar_internal_metadata" do
        app_file "db/schema.rb", ""
        rails "db:setup"

        test_environment = lambda { rails("runner", "-e", "test", "puts ActiveRecord::InternalMetadata[:environment]").strip }
        development_environment = lambda { rails("runner", "puts ActiveRecord::InternalMetadata[:environment]").strip }

        assert_equal "test", test_environment.call
        assert_equal "development", development_environment.call

        app_file "db/structure.sql", ""
        app_file "config/initializers/enable_sql_schema_format.rb", <<-RUBY
          Rails.application.config.active_record.schema_format = :sql
        RUBY

        rails "db:setup"

        assert_equal "test", test_environment.call
        assert_equal "development", development_environment.call
      end

      test "db:test:prepare sets test ar_internal_metadata" do
        app_file "db/schema.rb", ""
        rails "db:test:prepare"

        test_environment = lambda { rails("runner", "-e", "test", "puts ActiveRecord::InternalMetadata[:environment]").strip }

        assert_equal "test", test_environment.call

        app_file "db/structure.sql", ""
        app_file "config/initializers/enable_sql_schema_format.rb", <<-RUBY
          Rails.application.config.active_record.schema_format = :sql
        RUBY

        rails "db:test:prepare"

        assert_equal "test", test_environment.call
      end

      test "db:seed:replant truncates all non-internal tables and loads the seeds" do
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          rails "db:migrate"
          require "#{app_path}/config/environment"
          Book.create!(title: "Remote")
          assert_equal 1, Book.count
          schema_migrations = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
          internal_metadata = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")

          app_file "db/seeds.rb", <<-RUBY
            Book.create!(title: "Rework")
            Book.create!(title: "Ruby Under a Microscope")
          RUBY

          rails "db:seed:replant"

          assert_equal(
            schema_migrations,
            ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
          )
          assert_equal(
            internal_metadata,
            ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")
          )
          assert_equal 2, Book.count
          assert_not_predicate Book.where(title: "Remote"), :exists?
          assert_predicate Book.where(title: "Rework"), :exists?
          assert_predicate Book.where(title: "Ruby Under a Microscope"), :exists?
        end
      end

      test "db:seed:replant does not truncate any tables and does not load the seeds when environment is protected" do
        with_rails_env "production" do
          Dir.chdir(app_path) do
            rails "generate", "model", "book", "title:string"
            rails "db:migrate"
            require "#{app_path}/config/environment"
            Book.create!(title: "Remote")
            assert_equal 1, Book.count
            schema_migrations = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
            internal_metadata = ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")
            books = ActiveRecord::Base.connection.execute("SELECT * from \"books\"")

            app_file "db/seeds.rb", <<-RUBY
              Book.create!(title: "Rework")
            RUBY

            output = rails("db:seed:replant", allow_failure: true)
            assert_match(/ActiveRecord::ProtectedEnvironmentError/, output)

            assert_equal(
              schema_migrations,
              ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.schema_migrations_table_name}\"")
            )
            assert_equal(
              internal_metadata,
              ActiveRecord::Base.connection.execute("SELECT * from \"#{ActiveRecord::Base.internal_metadata_table_name}\"")
            )
            assert_equal 1, Book.count
            assert_equal(books, ActiveRecord::Base.connection.execute("SELECT * from \"books\""))
            assert_not_predicate Book.where(title: "Rework"), :exists?
          end
        end
      end

      test "db:prepare setup the database" do
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          output = rails("db:prepare")
          assert_match(/CreateBooks: migrated/, output)

          output = rails("db:drop")
          assert_match(/Dropped database/, output)

          rails "generate", "model", "recipe", "title:string"
          output = rails("db:prepare")
          assert_match(/CreateBooks: migrated/, output)
          assert_match(/CreateRecipes: migrated/, output)
        end
      end

      test "db:prepare does not touch schema when dumping is disabled" do
        Dir.chdir(app_path) do
          rails "generate", "model", "book", "title:string"
          rails "db:create", "db:migrate"

          app_file "db/schema.rb", "Not touched"
          app_file "config/initializers/disable_dumping_schema.rb", <<-RUBY
            Rails.application.config.active_record.dump_schema_after_migration = false
          RUBY

          rails "db:prepare"

          assert_equal("Not touched", File.read("db/schema.rb").strip)
        end
      end
    end
  end
end
