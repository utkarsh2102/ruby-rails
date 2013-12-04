# encoding: utf-8

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class MysqlAdapterTest < ActiveRecord::TestCase
      def setup
        @conn = ActiveRecord::Base.connection
        @conn.exec_query('drop table if exists ex')
        @conn.exec_query(<<-eosql)
          CREATE TABLE `ex` (
            `id` int(11) DEFAULT NULL auto_increment PRIMARY KEY,
            `number` integer,
            `data` varchar(255))
        eosql
      end

      def test_valid_column
        column = @conn.columns('ex').find { |col| col.name == 'id' }
        assert @conn.valid_type?(column.type)
      end

      def test_invalid_column
        assert_not @conn.valid_type?(:foobar)
      end

      def test_client_encoding
        assert_equal Encoding::UTF_8, @conn.client_encoding
      end

      def test_exec_insert_number
        insert(@conn, 'number' => 10)

        result = @conn.exec_query('SELECT number FROM ex WHERE number = 10')

        assert_equal 1, result.rows.length
        # if there are no bind parameters, it will return a string (due to
        # the libmysql api)
        assert_equal '10', result.rows.last.last
      end

      def test_exec_insert_string
        str = 'いただきます！'
        insert(@conn, 'number' => 10, 'data' => str)

        result = @conn.exec_query('SELECT number, data FROM ex WHERE number = 10')

        value = result.rows.last.last

        # FIXME: this should probably be inside the mysql AR adapter?
        value.force_encoding(@conn.client_encoding)

        # The strings in this file are utf-8, so transcode to utf-8
        value.encode!(Encoding::UTF_8)

        assert_equal str, value
      end

      def test_tables_quoting
        @conn.tables(nil, "foo-bar", nil)
        flunk
      rescue => e
        # assertion for *quoted* database properly
        assert_match(/database 'foo-bar'/, e.inspect)
      end

      def test_pk_and_sequence_for
        pk, seq = @conn.pk_and_sequence_for('ex')
        assert_equal 'id', pk
        assert_equal @conn.default_sequence_name('ex', 'id'), seq
      end

      def test_pk_and_sequence_for_with_non_standard_primary_key
        @conn.exec_query('drop table if exists ex_with_non_standard_pk')
        @conn.exec_query(<<-eosql)
          CREATE TABLE `ex_with_non_standard_pk` (
            `code` INT(11) DEFAULT NULL auto_increment,
             PRIMARY KEY  (`code`))
        eosql
        pk, seq = @conn.pk_and_sequence_for('ex_with_non_standard_pk')
        assert_equal 'code', pk
        assert_equal @conn.default_sequence_name('ex_with_non_standard_pk', 'code'), seq
      end

      def test_pk_and_sequence_for_with_custom_index_type_pk
        @conn.exec_query('drop table if exists ex_with_custom_index_type_pk')
        @conn.exec_query(<<-eosql)
          CREATE TABLE `ex_with_custom_index_type_pk` (
            `id` INT(11) DEFAULT NULL auto_increment,
             PRIMARY KEY  USING BTREE (`id`))
        eosql
        pk, seq = @conn.pk_and_sequence_for('ex_with_custom_index_type_pk')
        assert_equal 'id', pk
        assert_equal @conn.default_sequence_name('ex_with_custom_index_type_pk', 'id'), seq
      end

      def test_tinyint_integer_typecasting
        @conn.exec_query('drop table if exists ex_with_non_boolean_tinyint_column')
        @conn.exec_query(<<-eosql)
          CREATE TABLE `ex_with_non_boolean_tinyint_column` (
            `status` TINYINT(4))
        eosql
        insert(@conn, { 'status' => 2 }, 'ex_with_non_boolean_tinyint_column')

        result = @conn.exec_query('SELECT status FROM ex_with_non_boolean_tinyint_column')

        assert_equal 2, result.column_types['status'].type_cast(result.last['status'])
      end

      def test_supports_extensions
        assert_not @conn.supports_extensions?, 'does not support extensions'
      end

      def test_respond_to_enable_extension
        assert @conn.respond_to?(:enable_extension)
      end

      def test_respond_to_disable_extension
        assert @conn.respond_to?(:disable_extension)
      end

      private
      def insert(ctx, data, table='ex')
        binds   = data.map { |name, value|
          [ctx.columns(table).find { |x| x.name == name }, value]
        }
        columns = binds.map(&:first).map(&:name)

        sql = "INSERT INTO #{table} (#{columns.join(", ")})
               VALUES (#{(['?'] * columns.length).join(', ')})"

        ctx.exec_insert(sql, 'SQL', binds)
      end
    end
  end
end
