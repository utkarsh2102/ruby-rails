require 'abstract_unit'
require 'active_support/core_ext/date'
require 'active_support/core_ext/date_time'
require 'active_support/core_ext/numeric/time'

class TimeTravelTest < ActiveSupport::TestCase
  class TimeSubclass < ::Time; end
  class DateSubclass < ::Date; end
  class DateTimeSubclass < ::DateTime; end

  def test_time_helper_travel
    Time.stubs(now: Time.now) do
      begin
        expected_time = Time.now + 1.day
        travel 1.day

        assert_equal expected_time.to_s(:db), Time.now.to_s(:db)
        assert_equal expected_time.to_date, Date.today
        assert_equal expected_time.to_datetime.to_s(:db), DateTime.now.to_s(:db)
      ensure
        travel_back
      end
    end
  end

  def test_time_helper_travel_with_block
    Time.stubs(now: Time.now) do
      begin
        expected_time = Time.now + 1.day

        travel 1.day do
          assert_equal expected_time.to_s(:db), Time.now.to_s(:db)
          assert_equal expected_time.to_date, Date.today
          assert_equal expected_time.to_datetime.to_s(:db), DateTime.now.to_s(:db)
        end

        assert_not_equal expected_time.to_s(:db), Time.now.to_s(:db)
        assert_not_equal expected_time.to_date, Date.today
        assert_not_equal expected_time.to_datetime.to_s(:db), DateTime.now.to_s(:db)
      ensure
        travel_back
      end
    end
  end

  def test_time_helper_travel_to
    Time.stubs(now: Time.now) do
      begin
        expected_time = Time.new(2004, 11, 24, 01, 04, 44)
        travel_to expected_time

        assert_equal expected_time, Time.now
        assert_equal Date.new(2004, 11, 24), Date.today
        assert_equal expected_time.to_datetime, DateTime.now
      ensure
        travel_back
      end
    end
  end

  def test_time_helper_travel_to_with_block
    Time.stubs(now: Time.now) do
      begin
        expected_time = Time.new(2004, 11, 24, 01, 04, 44)

        travel_to expected_time do
          assert_equal expected_time, Time.now
          assert_equal Date.new(2004, 11, 24), Date.today
          assert_equal expected_time.to_datetime, DateTime.now
        end

        assert_not_equal expected_time, Time.now
        assert_not_equal Date.new(2004, 11, 24), Date.today
        assert_not_equal expected_time.to_datetime, DateTime.now
      ensure
        travel_back
      end
    end
  end

  def test_time_helper_travel_back
    Time.stubs(now: Time.now) do
      begin
        expected_time = Time.new(2004, 11, 24, 01, 04, 44)

        travel_to expected_time
        assert_equal expected_time, Time.now
        assert_equal Date.new(2004, 11, 24), Date.today
        assert_equal expected_time.to_datetime, DateTime.now
        travel_back

        assert_not_equal expected_time, Time.now
        assert_not_equal Date.new(2004, 11, 24), Date.today
        assert_not_equal expected_time.to_datetime, DateTime.now
      ensure
        travel_back
      end
    end
  end

  def test_travel_to_will_reset_the_usec_to_avoid_mysql_rouding
    Time.stubs(now: Time.now) do
      begin
        travel_to Time.utc(2014, 10, 10, 10, 10, 50, 999999) do
          assert_equal 50, Time.now.sec
          assert_equal 0, Time.now.usec
          assert_equal 50, DateTime.now.sec
          assert_equal 0, DateTime.now.usec
        end
      ensure
        travel_back
      end
    end
  end

  def test_time_helper_travel_with_time_subclass
    assert_equal TimeSubclass, TimeSubclass.now.class
    assert_equal DateSubclass, DateSubclass.today.class
    assert_equal DateTimeSubclass, DateTimeSubclass.now.class

    travel 1.day do
      assert_equal TimeSubclass, TimeSubclass.now.class
      assert_equal DateSubclass, DateSubclass.today.class
      assert_equal DateTimeSubclass, DateTimeSubclass.now.class
      assert_equal Time.now.to_s, TimeSubclass.now.to_s
      assert_equal Date.today.to_s, DateSubclass.today.to_s
      assert_equal DateTime.now.to_s, DateTimeSubclass.now.to_s
    end
  end
end
