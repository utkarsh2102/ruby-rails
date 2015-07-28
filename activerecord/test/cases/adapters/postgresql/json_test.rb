# encoding: utf-8
require "cases/helper"
require 'support/schema_dumping_helper'

module PostgresqlJSONSharedTestCases
  include SchemaDumpingHelper

  class JsonDataType < ActiveRecord::Base
    self.table_name = 'json_data_type'

    store_accessor :settings, :resolution
  end

  def setup
    @connection = ActiveRecord::Base.connection
    begin
      @connection.transaction do
        @connection.create_table('json_data_type') do |t|
          t.public_send column_type, 'payload', default: {} # t.json 'payload', default: {}
          t.public_send column_type, 'settings'             # t.json 'settings'
        end
      end
    rescue ActiveRecord::StatementInvalid
      skip "do not test on PG without json"
    end
    @column = JsonDataType.columns_hash['payload']
  end

  def teardown
    @connection.execute 'drop table if exists json_data_type'
  end

  def test_column
    column = JsonDataType.columns_hash["payload"]
    assert_equal column_type, column.type
    assert_equal column_type.to_s, column.sql_type
    assert_not column.number?
    assert_not column.binary?
    assert_not column.array
  end

  def test_default
    @connection.add_column 'json_data_type', 'permissions', column_type, default: '{"users": "read", "posts": ["read", "write"]}'
    JsonDataType.reset_column_information

    assert_equal({"users"=>"read", "posts"=>["read", "write"]}, JsonDataType.column_defaults['permissions'])
    assert_equal({"users"=>"read", "posts"=>["read", "write"]}, JsonDataType.new.permissions)
  ensure
    JsonDataType.reset_column_information
  end

  def test_change_table_supports_json
    @connection.transaction do
      @connection.change_table('json_data_type') do |t|
        t.public_send column_type, 'users', default: '{}' # t.json 'users', default: '{}'
      end
      JsonDataType.reset_column_information
      column = JsonDataType.columns_hash['users']
      assert_equal column_type, column.type

      raise ActiveRecord::Rollback # reset the schema change
    end
  ensure
    JsonDataType.reset_column_information
  end

  def test_schema_dumping
    output = dump_table_schema("json_data_type")
    assert_match(/t.#{column_type.to_s}\s+"payload",\s+default: {}/, output)
  end

  def test_cast_value_on_write
    x = JsonDataType.new payload: {"string" => "foo", :symbol => :bar}
    assert_equal({"string" => "foo", :symbol => :bar}, x.payload_before_type_cast)
    assert_equal({"string" => "foo", "symbol" => "bar"}, x.payload)
    x.save
    assert_equal({"string" => "foo", "symbol" => "bar"}, x.reload.payload)
  end

  def test_type_cast_json
    column = JsonDataType.columns_hash["payload"]

    data = "{\"a_key\":\"a_value\"}"
    hash = column.type_cast_from_database(data)
    assert_equal({'a_key' => 'a_value'}, hash)
    assert_equal({'a_key' => 'a_value'}, column.type_cast_from_database(data))

    assert_equal({}, column.type_cast_from_database("{}"))
    assert_equal({'key'=>nil}, column.type_cast_from_database('{"key": null}'))
    assert_equal({'c'=>'}','"a"'=>'b "a b'}, column.type_cast_from_database(%q({"c":"}", "\"a\"":"b \"a b"})))
  end

  def test_rewrite
    @connection.execute "insert into json_data_type (payload) VALUES ('{\"k\":\"v\"}')"
    x = JsonDataType.first
    x.payload = { '"a\'' => 'b' }
    assert x.save!
  end

  def test_select
    @connection.execute "insert into json_data_type (payload) VALUES ('{\"k\":\"v\"}')"
    x = JsonDataType.first
    assert_equal({'k' => 'v'}, x.payload)
  end

  def test_select_multikey
    @connection.execute %q|insert into json_data_type (payload) VALUES ('{"k1":"v1", "k2":"v2", "k3":[1,2,3]}')|
    x = JsonDataType.first
    assert_equal({'k1' => 'v1', 'k2' => 'v2', 'k3' => [1,2,3]}, x.payload)
  end

  def test_null_json
    @connection.execute %q|insert into json_data_type (payload) VALUES(null)|
    x = JsonDataType.first
    assert_equal(nil, x.payload)
  end

  def test_select_array_json_value
    @connection.execute %q|insert into json_data_type (payload) VALUES ('["v0",{"k1":"v1"}]')|
    x = JsonDataType.first
    assert_equal(['v0', {'k1' => 'v1'}], x.payload)
  end

  def test_rewrite_array_json_value
    @connection.execute %q|insert into json_data_type (payload) VALUES ('["v0",{"k1":"v1"}]')|
    x = JsonDataType.first
    x.payload = ['v1', {'k2' => 'v2'}, 'v3']
    assert x.save!
  end

  def test_with_store_accessors
    x = JsonDataType.new(resolution: "320×480")
    assert_equal "320×480", x.resolution

    x.save!
    x = JsonDataType.first
    assert_equal "320×480", x.resolution

    x.resolution = "640×1136"
    x.save!

    x = JsonDataType.first
    assert_equal "640×1136", x.resolution
  end

  def test_duplication_with_store_accessors
    x = JsonDataType.new(resolution: "320×480")
    assert_equal "320×480", x.resolution

    y = x.dup
    assert_equal "320×480", y.resolution
  end

  def test_yaml_round_trip_with_store_accessors
    x = JsonDataType.new(resolution: "320×480")
    assert_equal "320×480", x.resolution

    y = YAML.load(YAML.dump(x))
    assert_equal "320×480", y.resolution
  end

  def test_changes_in_place
    json = JsonDataType.new
    assert_not json.changed?

    json.payload = { 'one' => 'two' }
    assert json.changed?
    assert json.payload_changed?

    json.save!
    assert_not json.changed?

    json.payload['three'] = 'four'
    assert json.payload_changed?

    json.save!
    json.reload

    assert_equal({ 'one' => 'two', 'three' => 'four' }, json.payload)
    assert_not json.changed?
  end

  def test_assigning_invalid_json
    json = JsonDataType.new

    json.payload = 'foo'

    assert_nil json.payload
  end
end

class PostgresqlJSONTest < ActiveRecord::TestCase
  include PostgresqlJSONSharedTestCases

  def column_type
    :json
  end
end

class PostgresqlJSONBTest < ActiveRecord::TestCase
  include PostgresqlJSONSharedTestCases

  def column_type
    :jsonb
  end
end
