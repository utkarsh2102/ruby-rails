# encoding: utf-8
require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class PostgreSQLAdapterTest < ActiveRecord::TestCase
      def setup
        @connection = ActiveRecord::Base.connection
      end

      def test_bad_connection
        assert_raise ActiveRecord::NoDatabaseError do
          configuration = ActiveRecord::Base.configurations['arunit'].merge(database: 'should_not_exist-cinco-dog-db')
          connection = ActiveRecord::Base.postgresql_connection(configuration)
          connection.exec_query('SELECT 1')
        end
      end

      def test_valid_column
        with_example_table do
          column = @connection.columns('ex').find { |col| col.name == 'id' }
          assert @connection.valid_type?(column.type)
        end
      end

      def test_invalid_column
        assert_not @connection.valid_type?(:foobar)
      end

      def test_primary_key
        with_example_table do
          assert_equal 'id', @connection.primary_key('ex')
        end
      end

      def test_primary_key_works_tables_containing_capital_letters
        assert_equal 'id', @connection.primary_key('CamelCase')
      end

      def test_non_standard_primary_key
        with_example_table 'data character varying(255) primary key' do
          assert_equal 'data', @connection.primary_key('ex')
        end
      end

      def test_primary_key_returns_nil_for_no_pk
        with_example_table 'id integer' do
          assert_nil @connection.primary_key('ex')
        end
      end

      def test_primary_key_raises_error_if_table_not_found
        assert_raises(ActiveRecord::StatementInvalid) do
          @connection.primary_key('unobtainium')
        end
      end

      def test_insert_sql_with_proprietary_returning_clause
        with_example_table do
          id = @connection.insert_sql("insert into ex (number) values(5150)", nil, "number")
          assert_equal "5150", id
        end
      end

      def test_insert_sql_with_quoted_schema_and_table_name
        with_example_table do
          id = @connection.insert_sql('insert into "public"."ex" (number) values(5150)')
          expect = @connection.query('select max(id) from ex').first.first
          assert_equal expect, id
        end
      end

      def test_insert_sql_with_no_space_after_table_name
        with_example_table do
          id = @connection.insert_sql("insert into ex(number) values(5150)")
          expect = @connection.query('select max(id) from ex').first.first
          assert_equal expect, id
        end
      end

      def test_multiline_insert_sql
        with_example_table do
          id = @connection.insert_sql(<<-SQL)
          insert into ex(
                         number)
          values(
                 5152
                 )
          SQL
          expect = @connection.query('select max(id) from ex').first.first
          assert_equal expect, id
        end
      end

      def test_insert_sql_with_returning_disabled
        connection = connection_without_insert_returning
        id = connection.insert_sql("insert into postgresql_partitioned_table_parent (number) VALUES (1)")
        expect = connection.query('select max(id) from postgresql_partitioned_table_parent').first.first
        assert_equal expect, id
      end

      def test_exec_insert_with_returning_disabled
        connection = connection_without_insert_returning
        result = connection.exec_insert("insert into postgresql_partitioned_table_parent (number) VALUES (1)", nil, [], 'id', 'postgresql_partitioned_table_parent_id_seq')
        expect = connection.query('select max(id) from postgresql_partitioned_table_parent').first.first
        assert_equal expect, result.rows.first.first
      end

      def test_exec_insert_with_returning_disabled_and_no_sequence_name_given
        connection = connection_without_insert_returning
        result = connection.exec_insert("insert into postgresql_partitioned_table_parent (number) VALUES (1)", nil, [], 'id')
        expect = connection.query('select max(id) from postgresql_partitioned_table_parent').first.first
        assert_equal expect, result.rows.first.first
      end

      def test_sql_for_insert_with_returning_disabled
        connection = connection_without_insert_returning
        result = connection.sql_for_insert('sql', nil, nil, nil, 'binds')
        assert_equal ['sql', 'binds'], result
      end

      def test_serial_sequence
        assert_equal 'public.accounts_id_seq',
          @connection.serial_sequence('accounts', 'id')

        assert_raises(ActiveRecord::StatementInvalid) do
          @connection.serial_sequence('zomg', 'id')
        end
      end

      def test_default_sequence_name
        assert_equal 'accounts_id_seq',
          @connection.default_sequence_name('accounts', 'id')

        assert_equal 'accounts_id_seq',
          @connection.default_sequence_name('accounts')
      end

      def test_default_sequence_name_bad_table
        assert_equal 'zomg_id_seq',
          @connection.default_sequence_name('zomg', 'id')

        assert_equal 'zomg_id_seq',
          @connection.default_sequence_name('zomg')
      end

      def test_pk_and_sequence_for
        with_example_table do
          pk, seq = @connection.pk_and_sequence_for('ex')
          assert_equal 'id', pk
          assert_equal @connection.default_sequence_name('ex', 'id'), seq
        end
      end

      def test_pk_and_sequence_for_with_non_standard_primary_key
        with_example_table 'code serial primary key' do
          pk, seq = @connection.pk_and_sequence_for('ex')
          assert_equal 'code', pk
          assert_equal @connection.default_sequence_name('ex', 'code'), seq
        end
      end

      def test_pk_and_sequence_for_returns_nil_if_no_seq
        with_example_table 'id integer primary key' do
          assert_nil @connection.pk_and_sequence_for('ex')
        end
      end

      def test_pk_and_sequence_for_returns_nil_if_no_pk
        with_example_table 'id integer' do
          assert_nil @connection.pk_and_sequence_for('ex')
        end
      end

      def test_pk_and_sequence_for_returns_nil_if_table_not_found
        assert_nil @connection.pk_and_sequence_for('unobtainium')
      end

      def test_exec_insert_number
        with_example_table do
          insert(@connection, 'number' => 10)

          result = @connection.exec_query('SELECT number FROM ex WHERE number = 10')

          assert_equal 1, result.rows.length
          assert_equal "10", result.rows.last.last
        end
      end

      def test_exec_insert_string
        with_example_table do
          str = 'いただきます！'
          insert(@connection, 'number' => 10, 'data' => str)

          result = @connection.exec_query('SELECT number, data FROM ex WHERE number = 10')

          value = result.rows.last.last

          assert_equal str, value
        end
      end

      def test_table_alias_length
        assert_nothing_raised do
          @connection.table_alias_length
        end
      end

      def test_exec_no_binds
        with_example_table do
          result = @connection.exec_query('SELECT id, data FROM ex')
          assert_equal 0, result.rows.length
          assert_equal 2, result.columns.length
          assert_equal %w{ id data }, result.columns

          string = @connection.quote('foo')
          @connection.exec_query("INSERT INTO ex (id, data) VALUES (1, #{string})")
          result = @connection.exec_query('SELECT id, data FROM ex')
          assert_equal 1, result.rows.length
          assert_equal 2, result.columns.length

          assert_equal [['1', 'foo']], result.rows
        end
      end

      def test_exec_with_binds
        with_example_table do
          string = @connection.quote('foo')
          @connection.exec_query("INSERT INTO ex (id, data) VALUES (1, #{string})")
          result = @connection.exec_query(
                                          'SELECT id, data FROM ex WHERE id = $1', nil, [[nil, 1]])

          assert_equal 1, result.rows.length
          assert_equal 2, result.columns.length

          assert_equal [['1', 'foo']], result.rows
        end
      end

      def test_exec_typecasts_bind_vals
        with_example_table do
          string = @connection.quote('foo')
          @connection.exec_query("INSERT INTO ex (id, data) VALUES (1, #{string})")

          column = @connection.columns('ex').find { |col| col.name == 'id' }
          result = @connection.exec_query(
                                          'SELECT id, data FROM ex WHERE id = $1', nil, [[column, '1-fuu']])

          assert_equal 1, result.rows.length
          assert_equal 2, result.columns.length

          assert_equal [['1', 'foo']], result.rows
        end
      end

      def test_substitute_at
        bind = @connection.substitute_at(nil, 0)
        assert_equal Arel.sql('$1'), bind

        bind = @connection.substitute_at(nil, 1)
        assert_equal Arel.sql('$2'), bind
      end

      def test_partial_index
        with_example_table do
          @connection.add_index 'ex', %w{ id number }, :name => 'partial', :where => "number > 100"
          index = @connection.indexes('ex').find { |idx| idx.name == 'partial' }
          assert_equal "(number > 100)", index.where
        end
      end

      def test_columns_for_distinct_zero_orders
        assert_equal "posts.id",
          @connection.columns_for_distinct("posts.id", [])
      end

      def test_columns_for_distinct_one_order
        assert_equal "posts.id, posts.created_at AS alias_0",
          @connection.columns_for_distinct("posts.id", ["posts.created_at desc"])
      end

      def test_columns_for_distinct_few_orders
        assert_equal "posts.id, posts.created_at AS alias_0, posts.position AS alias_1",
          @connection.columns_for_distinct("posts.id", ["posts.created_at desc", "posts.position asc"])
      end

      def test_columns_for_distinct_with_case
        assert_equal(
          'posts.id, CASE WHEN author.is_active THEN UPPER(author.name) ELSE UPPER(author.email) END AS alias_0',
          @connection.columns_for_distinct('posts.id',
            ["CASE WHEN author.is_active THEN UPPER(author.name) ELSE UPPER(author.email) END"])
        )
      end

      def test_columns_for_distinct_blank_not_nil_orders
        assert_equal "posts.id, posts.created_at AS alias_0",
          @connection.columns_for_distinct("posts.id", ["posts.created_at desc", "", "   "])
      end

      def test_columns_for_distinct_with_arel_order
        order = Object.new
        def order.to_sql
          "posts.created_at desc"
        end
        assert_equal "posts.id, posts.created_at AS alias_0",
          @connection.columns_for_distinct("posts.id", [order])
      end

      def test_columns_for_distinct_with_nulls
        assert_equal "posts.title, posts.updater_id AS alias_0", @connection.columns_for_distinct("posts.title", ["posts.updater_id desc nulls first"])
        assert_equal "posts.title, posts.updater_id AS alias_0", @connection.columns_for_distinct("posts.title", ["posts.updater_id desc nulls last"])
      end

      def test_columns_for_distinct_without_order_specifiers
        assert_equal "posts.title, posts.updater_id AS alias_0",
          @connection.columns_for_distinct("posts.title", ["posts.updater_id"])

        assert_equal "posts.title, posts.updater_id AS alias_0",
          @connection.columns_for_distinct("posts.title", ["posts.updater_id nulls last"])

        assert_equal "posts.title, posts.updater_id AS alias_0",
          @connection.columns_for_distinct("posts.title", ["posts.updater_id nulls first"])
      end

      def test_raise_error_when_cannot_translate_exception
        assert_raise TypeError do
          @connection.send(:log, nil) { @connection.execute(nil) }
        end
      end

      def test_only_warn_on_first_encounter_of_unknown_oid
        warning = capture(:stderr) {
          @connection.select_all "SELECT NULL::anyelement"
          @connection.select_all "SELECT NULL::anyelement"
          @connection.select_all "SELECT NULL::anyelement"
        }
        assert_match(/\Aunknown OID \d+: failed to recognize type of 'anyelement'. It will be treated as String.\n\z/, warning)
      end

      private
      def insert(ctx, data)
        binds   = data.map { |name, value|
          [ctx.columns('ex').find { |x| x.name == name }, value]
        }
        columns = binds.map(&:first).map(&:name)

        bind_subs = columns.length.times.map { |x| "$#{x + 1}" }

        sql = "INSERT INTO ex (#{columns.join(", ")})
               VALUES (#{bind_subs.join(', ')})"

        ctx.exec_insert(sql, 'SQL', binds)
      end

      def with_example_table(definition = nil)
        definition ||= 'id serial primary key, number integer, data character varying(255)'
        @connection.exec_query("create table ex(#{definition})")
        yield
      ensure
        @connection.exec_query('drop table if exists ex')
      end

      def connection_without_insert_returning
        ActiveRecord::Base.postgresql_connection(ActiveRecord::Base.configurations['arunit'].merge(:insert_returning => false))
      end
    end
  end
end
