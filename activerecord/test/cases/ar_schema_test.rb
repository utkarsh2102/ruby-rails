require "cases/helper"

if ActiveRecord::Base.connection.supports_migrations?

  class ActiveRecordSchemaTest < ActiveRecord::TestCase
    self.use_transactional_fixtures = false

    def setup
      @connection = ActiveRecord::Base.connection
      ActiveRecord::SchemaMigration.drop_table
    end

    def teardown
      @connection.drop_table :fruits rescue nil
      @connection.drop_table :nep_fruits rescue nil
      @connection.drop_table :nep_schema_migrations rescue nil
      ActiveRecord::SchemaMigration.delete_all rescue nil
    end

    def test_has_no_primary_key
      old_primary_key_prefix_type = ActiveRecord::Base.primary_key_prefix_type
      ActiveRecord::Base.primary_key_prefix_type = :table_name_with_underscore
      assert_nil ActiveRecord::SchemaMigration.primary_key

      ActiveRecord::SchemaMigration.create_table
      assert_difference "ActiveRecord::SchemaMigration.count", 1 do
        ActiveRecord::SchemaMigration.create version: 12
      end
    ensure
      ActiveRecord::SchemaMigration.drop_table
      ActiveRecord::Base.primary_key_prefix_type = old_primary_key_prefix_type
    end

    def test_schema_define
      ActiveRecord::Schema.define(:version => 7) do
        create_table :fruits do |t|
          t.column :color, :string
          t.column :fruit_size, :string  # NOTE: "size" is reserved in Oracle
          t.column :texture, :string
          t.column :flavor, :string
        end
      end

      assert_nothing_raised { @connection.select_all "SELECT * FROM fruits" }
      assert_nothing_raised { @connection.select_all "SELECT * FROM schema_migrations" }
      assert_equal 7, ActiveRecord::Migrator::current_version
    end

    def test_schema_define_w_table_name_prefix
      table_name = ActiveRecord::SchemaMigration.table_name
      ActiveRecord::Base.table_name_prefix  = "nep_"
      ActiveRecord::SchemaMigration.table_name = "nep_#{table_name}"
      ActiveRecord::Schema.define(:version => 7) do
        create_table :fruits do |t|
          t.column :color, :string
          t.column :fruit_size, :string  # NOTE: "size" is reserved in Oracle
          t.column :texture, :string
          t.column :flavor, :string
        end
      end
      assert_equal 7, ActiveRecord::Migrator::current_version
    ensure
      ActiveRecord::Base.table_name_prefix  = ""
      ActiveRecord::SchemaMigration.table_name = table_name
    end

    def test_schema_raises_an_error_for_invalid_column_type
      assert_raise NoMethodError do
        ActiveRecord::Schema.define(:version => 8) do
          create_table :vegetables do |t|
            t.unknown :color
          end
        end
      end
    end

    def test_schema_subclass
      Class.new(ActiveRecord::Schema).define(:version => 9) do
        create_table :fruits
      end
      assert_nothing_raised { @connection.select_all "SELECT * FROM fruits" }
    end

    def test_normalize_version
      assert_equal "118", ActiveRecord::SchemaMigration.normalize_migration_number("0000118")
      assert_equal "002", ActiveRecord::SchemaMigration.normalize_migration_number("2")
      assert_equal "017", ActiveRecord::SchemaMigration.normalize_migration_number("0017")
      assert_equal "20131219224947", ActiveRecord::SchemaMigration.normalize_migration_number("20131219224947")
    end
  end
end
