require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class ReaperTest < ActiveRecord::TestCase
      attr_reader :pool

      def setup
        super
        @pool = ConnectionPool.new ActiveRecord::Base.connection_pool.spec
      end

      def teardown
        super
        @pool.connections.each(&:close)
      end

      class FakePool
        attr_reader :reaped

        def initialize
          @reaped = false
        end

        def reap
          @reaped = true
        end
      end

      # A reaper with nil time should never reap connections
      def test_nil_time
        fp = FakePool.new
        assert !fp.reaped
        reaper = ConnectionPool::Reaper.new(fp, nil)
        reaper.run
        assert !fp.reaped
      end

      def test_some_time
        fp = FakePool.new
        assert !fp.reaped

        reaper = ConnectionPool::Reaper.new(fp, 0.0001)
        reaper.run
        until fp.reaped
          Thread.pass
        end
        assert fp.reaped
      end

      def test_pool_has_reaper
        assert pool.reaper
      end

      def test_reaping_frequency_configuration
        spec = ActiveRecord::Base.connection_pool.spec.dup
        spec.config[:reaping_frequency] = 100
        pool = ConnectionPool.new spec
        assert_equal 100, pool.reaper.frequency
      end

      def test_connection_pool_starts_reaper
        spec = ActiveRecord::Base.connection_pool.spec.dup
        spec.config[:reaping_frequency] = 0.0001

        pool = ConnectionPool.new spec
        pool.dead_connection_timeout = 0

        conn = pool.checkout
        count = pool.connections.length

        conn.extend(Module.new { def active_threadsafe?; false; end; })

        while count == pool.connections.length
          Thread.pass
        end
        assert_equal(count - 1, pool.connections.length)
      end
    end
  end
end
