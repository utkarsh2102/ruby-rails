# encoding: utf-8
require 'cases/helper'

if ActiveRecord::Base.connection.supports_extensions?
  class PostgresqlCitextTest < ActiveRecord::TestCase
    class Citext < ActiveRecord::Base
      self.table_name = 'citexts'
    end

    def setup
      @connection = ActiveRecord::Base.connection

      enable_extension!('citext', @connection)

      @connection.create_table('citexts') do |t|
        t.citext 'cival'
      end
    end

    teardown do
      @connection.execute 'DROP TABLE IF EXISTS citexts;'
      disable_extension!('citext', @connection)
    end

    def test_citext_enabled
      assert @connection.extension_enabled?('citext')
    end

    def test_column
      column = Citext.columns_hash['cival']
      assert_equal :citext, column.type
      assert_equal 'citext', column.sql_type
      assert_not column.number?
      assert_not column.binary?
      assert_not column.array
    end

    def test_change_table_supports_json
      @connection.transaction do
        @connection.change_table('citexts') do |t|
          t.citext 'username'
        end
        Citext.reset_column_information
        column = Citext.columns_hash['username']
        assert_equal :citext, column.type

        raise ActiveRecord::Rollback # reset the schema change
      end
    ensure
      Citext.reset_column_information
    end

    def test_write
      x = Citext.new(cival: 'Some CI Text')
      x.save!
      citext = Citext.first
      assert_equal "Some CI Text", citext.cival

      citext.cival = "Some NEW CI Text"
      citext.save!

      assert_equal "Some NEW CI Text", citext.reload.cival
    end

    def test_select_case_insensitive
      @connection.execute "insert into citexts (cival) values('Cased Text')"
      x = Citext.where(cival: 'cased text').first
      assert_equal 'Cased Text', x.cival
    end
  end
end
