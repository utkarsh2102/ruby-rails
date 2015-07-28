require 'isolation/abstract_unit'

module ApplicationTests
  class BinSetupTest < ActiveSupport::TestCase
    include ActiveSupport::Testing::Isolation

    def setup
      build_app
    end

    def teardown
      teardown_app
    end

    def test_bin_setup
      Dir.chdir(app_path) do
        app_file 'db/schema.rb', <<-RUBY
          ActiveRecord::Schema.define(version: 20140423102712) do
            create_table(:articles) {}
          end
        RUBY

        list_tables = lambda { `bin/rails runner 'p ActiveRecord::Base.connection.tables'`.strip }
        File.write("log/my.log", "zomg!")

        assert_equal '[]', list_tables.call
        assert File.exist?("log/my.log")
        assert_not File.exist?("tmp/restart.txt")
        `bin/setup 2>&1`
        assert_not File.exist?("log/my.log")
        assert_equal '["articles", "schema_migrations"]', list_tables.call
        assert File.exist?("tmp/restart.txt")
      end
    end

    def test_bin_setup_output
      Dir.chdir(app_path) do
        app_file 'db/schema.rb', ""

        output = `bin/setup 2>&1`
        assert_equal(<<-OUTPUT, output)
== Installing dependencies ==
The Gemfile's dependencies are satisfied

== Preparing database ==

== Removing old logs and tempfiles ==

== Restarting application server ==
        OUTPUT
      end
    end
  end
end
