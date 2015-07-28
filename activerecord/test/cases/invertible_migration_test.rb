require "cases/helper"

module ActiveRecord
  class InvertibleMigrationTest < ActiveRecord::TestCase
    class SilentMigration < ActiveRecord::Migration
      def write(text = '')
        # sssshhhhh!!
      end
    end

    class InvertibleMigration < SilentMigration
      def change
        create_table("horses") do |t|
          t.column :content, :text
          t.column :remind_at, :datetime
        end
      end
    end

    class InvertibleRevertMigration < SilentMigration
      def change
        revert do
          create_table("horses") do |t|
            t.column :content, :text
            t.column :remind_at, :datetime
          end
        end
      end
    end

    class InvertibleByPartsMigration < SilentMigration
      attr_writer :test
      def change
        create_table("new_horses") do |t|
          t.column :breed, :string
        end
        reversible do |dir|
          @test.yield :both
          dir.up    { @test.yield :up }
          dir.down  { @test.yield :down }
        end
        revert do
          create_table("horses") do |t|
            t.column :content, :text
            t.column :remind_at, :datetime
          end
        end
      end
    end

    class NonInvertibleMigration < SilentMigration
      def change
        create_table("horses") do |t|
          t.column :content, :text
          t.column :remind_at, :datetime
        end
        remove_column "horses", :content
      end
    end

    class RemoveIndexMigration1 < SilentMigration
      def self.up
        create_table("horses") do |t|
          t.column :name, :string
          t.column :color, :string
          t.index [:name, :color]
        end
      end
    end

    class RemoveIndexMigration2 < SilentMigration
      def change
        change_table("horses") do |t|
          t.remove_index [:name, :color]
        end
      end
    end

    class LegacyMigration < ActiveRecord::Migration
      def self.up
        create_table("horses") do |t|
          t.column :content, :text
          t.column :remind_at, :datetime
        end
      end

      def self.down
        drop_table("horses")
      end
    end

    class RevertWholeMigration < SilentMigration
      def initialize(name = self.class.name, version = nil, migration)
        @migration = migration
        super(name, version)
      end

      def change
        revert @migration
      end
    end

    class NestedRevertWholeMigration < RevertWholeMigration
      def change
        revert { super }
      end
    end

    class RevertNamedIndexMigration1 < SilentMigration
      def change
        create_table("horses") do |t|
          t.column :content, :string
          t.column :remind_at, :datetime
        end
        add_index :horses, :content
      end
    end

    class RevertNamedIndexMigration2 < SilentMigration
      def change
        add_index :horses, :content, name: "horses_index_named"
      end
    end

    setup do
      @verbose_was, ActiveRecord::Migration.verbose = ActiveRecord::Migration.verbose, false
    end

    teardown do
      %w[horses new_horses].each do |table|
        if ActiveRecord::Base.connection.table_exists?(table)
          ActiveRecord::Base.connection.drop_table(table)
        end
      end
      ActiveRecord::Migration.verbose = @verbose_was
    end

    def test_no_reverse
      migration = NonInvertibleMigration.new
      migration.migrate(:up)
      assert_raises(IrreversibleMigration) do
        migration.migrate(:down)
      end
    end

    def test_exception_on_removing_index_without_column_option
      RemoveIndexMigration1.new.migrate(:up)
      migration = RemoveIndexMigration2.new
      migration.migrate(:up)

      assert_raises(IrreversibleMigration) do
        migration.migrate(:down)
      end
    end

    def test_migrate_up
      migration = InvertibleMigration.new
      migration.migrate(:up)
      assert migration.connection.table_exists?("horses"), "horses should exist"
    end

    def test_migrate_down
      migration = InvertibleMigration.new
      migration.migrate :up
      migration.migrate :down
      assert !migration.connection.table_exists?("horses")
    end

    def test_migrate_revert
      migration = InvertibleMigration.new
      revert = InvertibleRevertMigration.new
      migration.migrate :up
      revert.migrate :up
      assert !migration.connection.table_exists?("horses")
      revert.migrate :down
      assert migration.connection.table_exists?("horses")
      migration.migrate :down
      assert !migration.connection.table_exists?("horses")
    end

    def test_migrate_revert_by_part
      InvertibleMigration.new.migrate :up
      received = []
      migration = InvertibleByPartsMigration.new
      migration.test = ->(dir){
        assert migration.connection.table_exists?("horses")
        assert migration.connection.table_exists?("new_horses")
        received << dir
      }
      migration.migrate :up
      assert_equal [:both, :up], received
      assert !migration.connection.table_exists?("horses")
      assert migration.connection.table_exists?("new_horses")
      migration.migrate :down
      assert_equal [:both, :up, :both, :down], received
      assert migration.connection.table_exists?("horses")
      assert !migration.connection.table_exists?("new_horses")
    end

    def test_migrate_revert_whole_migration
      migration = InvertibleMigration.new
      [LegacyMigration, InvertibleMigration].each do |klass|
        revert = RevertWholeMigration.new(klass)
        migration.migrate :up
        revert.migrate :up
        assert !migration.connection.table_exists?("horses")
        revert.migrate :down
        assert migration.connection.table_exists?("horses")
        migration.migrate :down
        assert !migration.connection.table_exists?("horses")
      end
    end

    def test_migrate_nested_revert_whole_migration
      revert = NestedRevertWholeMigration.new(InvertibleRevertMigration)
      revert.migrate :down
      assert revert.connection.table_exists?("horses")
      revert.migrate :up
      assert !revert.connection.table_exists?("horses")
    end

    def test_revert_order
      block = Proc.new{|t| t.string :name }
      recorder = ActiveRecord::Migration::CommandRecorder.new(ActiveRecord::Base.connection)
      recorder.instance_eval do
        create_table("apples", &block)
        revert do
          create_table("bananas", &block)
          revert do
            create_table("clementines")
            create_table("dates")
          end
          create_table("elderberries")
        end
        revert do
          create_table("figs")
          create_table("grapes")
        end
      end
      assert_equal [[:create_table, ["apples"], block], [:drop_table, ["elderberries"], nil],
                    [:create_table, ["clementines"], nil], [:create_table, ["dates"], nil],
                    [:drop_table, ["bananas"], block], [:drop_table, ["grapes"], nil],
                    [:drop_table, ["figs"], nil]], recorder.commands
    end

    def test_legacy_up
      LegacyMigration.migrate :up
      assert ActiveRecord::Base.connection.table_exists?("horses"), "horses should exist"
    end

    def test_legacy_down
      LegacyMigration.migrate :up
      LegacyMigration.migrate :down
      assert !ActiveRecord::Base.connection.table_exists?("horses"), "horses should not exist"
    end

    def test_up
      LegacyMigration.up
      assert ActiveRecord::Base.connection.table_exists?("horses"), "horses should exist"
    end

    def test_down
      LegacyMigration.up
      LegacyMigration.down
      assert !ActiveRecord::Base.connection.table_exists?("horses"), "horses should not exist"
    end

    def test_migrate_down_with_table_name_prefix
      ActiveRecord::Base.table_name_prefix = 'p_'
      ActiveRecord::Base.table_name_suffix = '_s'
      migration = InvertibleMigration.new
      migration.migrate(:up)
      assert_nothing_raised { migration.migrate(:down) }
      assert !ActiveRecord::Base.connection.table_exists?("p_horses_s"), "p_horses_s should not exist"
    ensure
      ActiveRecord::Base.table_name_prefix = ActiveRecord::Base.table_name_suffix = ''
    end

    # MySQL 5.7 and Oracle do not allow to create duplicate indexes on the same columns
    unless current_adapter?(:MysqlAdapter, :Mysql2Adapter, :OracleAdapter)
      def test_migrate_revert_add_index_with_name
        RevertNamedIndexMigration1.new.migrate(:up)
        RevertNamedIndexMigration2.new.migrate(:up)
        RevertNamedIndexMigration2.new.migrate(:down)

        connection = ActiveRecord::Base.connection
        assert connection.index_exists?(:horses, :content),
               "index on content should exist"
        assert !connection.index_exists?(:horses, :content, name: "horses_index_named"),
              "horses_index_named index should not exist"
      end
    end

  end
end
