require "cases/helper"
require 'support/connection_helper'

module ActiveRecord
  class PostgresqlConnectionTest < ActiveRecord::TestCase
    include ConnectionHelper

    class NonExistentTable < ActiveRecord::Base
    end

    fixtures :comments

    def setup
      super
      @subscriber = SQLSubscriber.new
      @subscription = ActiveSupport::Notifications.subscribe('sql.active_record', @subscriber)
      @connection = ActiveRecord::Base.connection
    end

    def teardown
      ActiveSupport::Notifications.unsubscribe(@subscription)
      super
    end

    def test_truncate
      count = ActiveRecord::Base.connection.execute("select count(*) from comments").first['count'].to_i
      assert_operator count, :>, 0
      ActiveRecord::Base.connection.truncate("comments")
      count = ActiveRecord::Base.connection.execute("select count(*) from comments").first['count'].to_i
      assert_equal 0, count
    end

    def test_encoding
      assert_not_nil @connection.encoding
    end

    def test_collation
      assert_not_nil @connection.collation
    end

    def test_ctype
      assert_not_nil @connection.ctype
    end

    def test_default_client_min_messages
      assert_equal "warning", @connection.client_min_messages
    end

    # Ensure, we can set connection params using the example of Generic
    # Query Optimizer (geqo). It is 'on' per default.
    def test_connection_options
      params = ActiveRecord::Base.connection_config.dup
      params[:options] = "-c geqo=off"
      NonExistentTable.establish_connection(params)

      # Verify the connection param has been applied.
      expect = NonExistentTable.connection.query('show geqo').first.first
      assert_equal 'off', expect
    end

    def test_reset
      @connection.query('ROLLBACK')
      @connection.query('SET geqo TO off')

      # Verify the setting has been applied.
      expect = @connection.query('show geqo').first.first
      assert_equal 'off', expect

      @connection.reset!

      # Verify the setting has been cleared.
      expect = @connection.query('show geqo').first.first
      assert_equal 'on', expect
    end

    def test_reset_with_transaction
      @connection.query('ROLLBACK')
      @connection.query('SET geqo TO off')

      # Verify the setting has been applied.
      expect = @connection.query('show geqo').first.first
      assert_equal 'off', expect

      @connection.query('BEGIN')
      @connection.reset!

      # Verify the setting has been cleared.
      expect = @connection.query('show geqo').first.first
      assert_equal 'on', expect
    end

    def test_tables_logs_name
      @connection.tables('hello')
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_indexes_logs_name
      @connection.indexes('items', 'hello')
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_table_exists_logs_name
      @connection.table_exists?('items')
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_table_alias_length_logs_name
      @connection.instance_variable_set("@table_alias_length", nil)
      @connection.table_alias_length
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_current_database_logs_name
      @connection.current_database
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_encoding_logs_name
      @connection.encoding
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_schema_names_logs_name
      @connection.schema_names
      assert_equal 'SCHEMA', @subscriber.logged[0][1]
    end

    def test_statement_key_is_logged
      bindval = 1
      @connection.exec_query('SELECT $1::integer', 'SQL', [[nil, bindval]])
      name = @subscriber.payloads.last[:statement_name]
      assert name
      res = @connection.exec_query("EXPLAIN (FORMAT JSON) EXECUTE #{name}(#{bindval})")
      plan = res.column_types['QUERY PLAN'].type_cast_from_database res.rows.first.first
      assert_operator plan.length, :>, 0
    end

    # Must have PostgreSQL >= 9.2, or with_manual_interventions set to
    # true for this test to run.
    #
    # When prompted, restart the PostgreSQL server with the
    # "-m fast" option or kill the individual connection assuming
    # you know the incantation to do that.
    # To restart PostgreSQL 9.1 on OS X, installed via MacPorts, ...
    # sudo su postgres -c "pg_ctl restart -D /opt/local/var/db/postgresql91/defaultdb/ -m fast"
    def test_reconnection_after_actual_disconnection_with_verify
      original_connection_pid = @connection.query('select pg_backend_pid()')

      # Sanity check.
      assert @connection.active?

      if @connection.send(:postgresql_version) >= 90200
        secondary_connection = ActiveRecord::Base.connection_pool.checkout
        secondary_connection.query("select pg_terminate_backend(#{original_connection_pid.first.first})")
        ActiveRecord::Base.connection_pool.checkin(secondary_connection)
      elsif ARTest.config['with_manual_interventions']
        puts 'Kill the connection now (e.g. by restarting the PostgreSQL ' +
          'server with the "-m fast" option) and then press enter.'
        $stdin.gets
      else
        # We're not capable of terminating the backend ourselves, and
        # we're not allowed to seek assistance; bail out without
        # actually testing anything.
        return
      end

      @connection.verify!

      assert @connection.active?

      # If we get no exception here, then either we re-connected successfully, or
      # we never actually got disconnected.
      new_connection_pid = @connection.query('select pg_backend_pid()')

      assert_not_equal original_connection_pid, new_connection_pid,
        "umm -- looks like you didn't break the connection, because we're still " +
        "successfully querying with the same connection pid."

      # Repair all fixture connections so other tests won't break.
      @fixture_connections.each do |c|
        c.verify!
      end
    end

    def test_set_session_variable_true
      run_without_connection do |orig_connection|
        ActiveRecord::Base.establish_connection(orig_connection.deep_merge({:variables => {:debug_print_plan => true}}))
        set_true = ActiveRecord::Base.connection.exec_query "SHOW DEBUG_PRINT_PLAN"
        assert_equal set_true.rows, [["on"]]
      end
    end

    def test_set_session_variable_false
      run_without_connection do |orig_connection|
        ActiveRecord::Base.establish_connection(orig_connection.deep_merge({:variables => {:debug_print_plan => false}}))
        set_false = ActiveRecord::Base.connection.exec_query "SHOW DEBUG_PRINT_PLAN"
        assert_equal set_false.rows, [["off"]]
      end
    end

    def test_set_session_variable_nil
      run_without_connection do |orig_connection|
        # This should be a no-op that does not raise an error
        ActiveRecord::Base.establish_connection(orig_connection.deep_merge({:variables => {:debug_print_plan => nil}}))
      end
    end

    def test_set_session_variable_default
      run_without_connection do |orig_connection|
        # This should execute a query that does not raise an error
        ActiveRecord::Base.establish_connection(orig_connection.deep_merge({:variables => {:debug_print_plan => :default}}))
      end
    end
  end
end
