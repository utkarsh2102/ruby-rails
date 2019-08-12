# frozen_string_literal: true

require "cases/helper"
require "models/topic"
require "models/reply"
require "models/author"
require "models/post"

if ActiveRecord::Base.connection.prepared_statements
  module ActiveRecord
    class BindParameterTest < ActiveRecord::TestCase
      fixtures :topics, :authors, :author_addresses, :posts

      class LogListener
        attr_accessor :calls

        def initialize
          @calls = []
        end

        def call(*args)
          calls << args
        end
      end

      def setup
        super
        @connection = ActiveRecord::Base.connection
        @subscriber = LogListener.new
        @pk = Topic.columns_hash[Topic.primary_key]
        @subscription = ActiveSupport::Notifications.subscribe("sql.active_record", @subscriber)
      end

      def teardown
        ActiveSupport::Notifications.unsubscribe(@subscription)
      end

      def test_statement_cache
        @connection.clear_cache!

        topics = Topic.where(id: 1)
        assert_equal [1], topics.map(&:id)
        assert_includes statement_cache, to_sql_key(topics.arel)
      end

      def test_statement_cache_with_query_cache
        @connection.enable_query_cache!
        @connection.clear_cache!

        topics = Topic.where(id: 1)
        assert_equal [1], topics.map(&:id)
        assert_includes statement_cache, to_sql_key(topics.arel)
      ensure
        @connection.disable_query_cache!
      end

      def test_statement_cache_with_find_by
        @connection.clear_cache!

        assert_equal 1, Topic.find_by!(id: 1).id
        assert_equal 2, Reply.find_by!(id: 2).id

        topic_sql = cached_statement(Topic, [:id])
        assert_includes statement_cache, to_sql_key(topic_sql)

        e = assert_raise { cached_statement(Reply, [:id]) }
        assert_equal "Reply has no cached statement by [:id]", e.message
      end

      def test_statement_cache_with_in_clause
        @connection.clear_cache!

        topics = Topic.where(id: [1, 3])
        assert_equal [1, 3], topics.map(&:id)
        assert_not_includes statement_cache, to_sql_key(topics.arel)
      end

      def test_statement_cache_with_sql_string_literal
        @connection.clear_cache!

        topics = Topic.where("topics.id = ?", 1)
        assert_equal [1], topics.map(&:id)
        assert_not_includes statement_cache, to_sql_key(topics.arel)
      end

      def test_too_many_binds
        bind_params_length = @connection.send(:bind_params_length)
        topics = Topic.where(id: (1 .. bind_params_length).to_a << 2**63)
        assert_equal Topic.count, topics.count
      end

      def test_too_many_binds_with_query_cache
        @connection.enable_query_cache!

        bind_params_length = @connection.send(:bind_params_length)
        topics = Topic.where(id: (1 .. bind_params_length + 1).to_a)
        assert_equal Topic.count, topics.count

        topics = Topic.where.not(id: (1 .. bind_params_length + 1).to_a)
        assert_equal 0, topics.count
      ensure
        @connection.disable_query_cache!
      end

      def test_bind_from_join_in_subquery
        subquery = Author.joins(:thinking_posts).where(name: "David")
        scope = Author.from(subquery, "authors").where(id: 1)
        assert_equal 1, scope.count
      end

      def test_binds_are_logged
        sub   = Arel::Nodes::BindParam.new(1)
        binds = [Relation::QueryAttribute.new("id", 1, Type::Value.new)]
        sql   = "select * from topics where id = #{sub.to_sql}"

        @connection.exec_query(sql, "SQL", binds)

        message = @subscriber.calls.find { |args| args[4][:sql] == sql }
        assert_equal binds, message[4][:binds]
      end

      def test_find_one_uses_binds
        Topic.find(1)
        message = @subscriber.calls.find { |args| args[4][:binds].any? { |attr| attr.value == 1 } }
        assert message, "expected a message with binds"
      end

      def test_logs_binds_after_type_cast
        binds = [Relation::QueryAttribute.new("id", "10", Type::Integer.new)]
        assert_logs_binds(binds)
      end

      def test_logs_legacy_binds_after_type_cast
        binds = [[@pk, "10"]]
        assert_logs_binds(binds)
      end

      def test_deprecate_supports_statement_cache
        assert_deprecated { ActiveRecord::Base.connection.supports_statement_cache? }
      end

      private
        def to_sql_key(arel)
          sql = @connection.to_sql(arel)
          @connection.respond_to?(:sql_key, true) ? @connection.send(:sql_key, sql) : sql
        end

        def cached_statement(klass, key)
          cache = klass.send(:cached_find_by_statement, key) do
            raise "#{klass} has no cached statement by #{key.inspect}"
          end
          cache.send(:query_builder).instance_variable_get(:@sql)
        end

        def statement_cache
          @connection.instance_variable_get(:@statements).send(:cache)
        end

        def assert_logs_binds(binds)
          payload = {
            name: "SQL",
            sql: "select * from topics where id = ?",
            binds: binds,
            type_casted_binds: @connection.type_casted_binds(binds)
          }

          event = ActiveSupport::Notifications::Event.new(
            "foo",
            Time.now,
            Time.now,
            123,
            payload)

          logger = Class.new(ActiveRecord::LogSubscriber) {
            attr_reader :debugs

            def initialize
              super
              @debugs = []
            end

            def debug(str)
              @debugs << str
            end
          }.new

          logger.sql(event)
          assert_match([[@pk.name, 10]].inspect, logger.debugs.first)
        end
    end
  end
end
