# encoding: utf-8

require "cases/helper"
require 'active_record/base'
require 'active_record/connection_adapters/postgresql_adapter'

class PostgresqlUUIDTest < ActiveRecord::TestCase
  class UUID < ActiveRecord::Base
    self.table_name = 'pg_uuids'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    unless @connection.supports_extensions?
      return skip "do not test on PG without uuid-ossp"
    end

    unless @connection.extension_enabled?('uuid-ossp')
      @connection.enable_extension 'uuid-ossp'
      @connection.commit_db_transaction
    end

    @connection.reconnect!

    @connection.transaction do
      @connection.create_table('pg_uuids', id: :uuid) do |t|
        t.string 'name'
        t.uuid 'other_uuid', default: 'uuid_generate_v4()'
      end
    end
  end

  def teardown
    @connection.execute 'drop table if exists pg_uuids'
  end

  def test_id_is_uuid
    assert_equal :uuid, UUID.columns_hash['id'].type
    assert UUID.primary_key
  end

  def test_id_has_a_default
    u = UUID.create
    assert_not_nil u.id
  end

  def test_auto_create_uuid
    u = UUID.create
    u.reload
    assert_not_nil u.other_uuid
  end
end

class PostgresqlUUIDTestNilDefault < ActiveRecord::TestCase
  class UUID < ActiveRecord::Base
    self.table_name = 'pg_uuids'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    @connection.reconnect!

    @connection.transaction do
      @connection.create_table('pg_uuids', id: false) do |t|
        t.primary_key :id, :uuid, default: nil
        t.string 'name'
      end
    end
  end

  def teardown
    @connection.execute 'drop table if exists pg_uuids'
  end

  def test_id_allows_default_override_via_nil
    col_desc = @connection.execute("SELECT pg_get_expr(d.adbin, d.adrelid) as default
                                    FROM pg_attribute a
                                    LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
                                    WHERE a.attname='id' AND a.attrelid = 'pg_uuids'::regclass").first
    assert_nil col_desc["default"]
  end
end

class PostgresqlUUIDTestNilDefault < ActiveRecord::TestCase
  class UUID < ActiveRecord::Base
    self.table_name = 'pg_uuids'
  end

  def setup
    @connection = ActiveRecord::Base.connection

    @connection.reconnect!

    @connection.transaction do
      @connection.create_table('pg_uuids', id: false) do |t|
        t.primary_key :id, :uuid, default: nil
        t.string 'name'
      end
    end
  end

  def teardown
    @connection.execute 'drop table if exists pg_uuids'
  end

  def test_id_allows_default_override_via_nil
    col_desc = @connection.execute("SELECT pg_get_expr(d.adbin, d.adrelid) as default
                                    FROM pg_attribute a
                                    LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
                                    WHERE a.attname='id' AND a.attrelid = 'pg_uuids'::regclass").first
    assert_nil col_desc["default"]
  end
end
