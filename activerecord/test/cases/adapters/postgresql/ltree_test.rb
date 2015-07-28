# encoding: utf-8
require "cases/helper"

class PostgresqlLtreeTest < ActiveRecord::TestCase
  class Ltree < ActiveRecord::Base
    self.table_name = 'ltrees'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    enable_extension!('ltree', @connection)

    @connection.transaction do
      @connection.create_table('ltrees') do |t|
        t.ltree 'path'
      end
    end
  rescue ActiveRecord::StatementInvalid
    skip "do not test on PG without ltree"
  end

  teardown do
    @connection.execute 'drop table if exists ltrees'
  end

  def test_column
    column = Ltree.columns_hash['path']
    assert_equal :ltree, column.type
    assert_equal "ltree", column.sql_type
    assert_not column.number?
    assert_not column.binary?
    assert_not column.array
  end

  def test_write
    ltree = Ltree.new(path: '1.2.3.4')
    assert ltree.save!
  end

  def test_select
    @connection.execute "insert into ltrees (path) VALUES ('1.2.3')"
    ltree = Ltree.first
    assert_equal '1.2.3', ltree.path
  end
end
