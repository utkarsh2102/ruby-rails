# frozen_string_literal: true

require "abstract_unit"

class CurrentAttributesTest < ActiveSupport::TestCase
  Person = Struct.new(:id, :name, :time_zone)

  class Current < ActiveSupport::CurrentAttributes
    attribute :world, :account, :person, :request
    delegate :time_zone, to: :person

    before_reset { Session.previous = person.try(:id) }

    resets do
      Time.zone = "UTC"
      Session.current = nil
    end

    def account=(account)
      super
      self.person = "#{account}'s person"
    end

    def person=(person)
      super
      Time.zone = person.try(:time_zone)
      Session.current = person.try(:id)
    end

    def request
      "#{super} something"
    end

    def intro
      "#{person.name}, in #{time_zone}"
    end
  end

  class Session < ActiveSupport::CurrentAttributes
    attribute :current, :previous
  end

  setup do
    @original_time_zone = Time.zone
    Current.reset
    Session.reset
  end

  teardown do
    Time.zone = @original_time_zone
  end

  test "read and write attribute" do
    Current.world = "world/1"
    assert_equal "world/1", Current.world
  end

  test "read overwritten attribute method" do
    Current.request = "request/1"
    assert_equal "request/1 something", Current.request
  end

  test "set attribute via overwritten method" do
    Current.account = "account/1"
    assert_equal "account/1", Current.account
    assert_equal "account/1's person", Current.person
  end

  test "set auxiliary class via overwritten method" do
    Current.person = Person.new(42, "David", "Central Time (US & Canada)")
    assert_equal "Central Time (US & Canada)", Time.zone.name
    assert_equal 42, Session.current
  end

  test "resets auxiliary classes via callback" do
    Current.person = Person.new(42, "David", "Central Time (US & Canada)")
    assert_equal "Central Time (US & Canada)", Time.zone.name

    Current.reset
    assert_equal "UTC", Time.zone.name
    assert_nil Session.current
  end

  test "set auxiliary class based on current attributes via before callback" do
    Current.person = Person.new(42, "David", "Central Time (US & Canada)")
    assert_nil Session.previous
    assert_equal 42, Session.current

    Current.reset
    assert_equal 42, Session.previous
    assert_nil Session.current
  end

  test "set attribute only via scope" do
    Current.world = "world/1"

    Current.set(world: "world/2") do
      assert_equal "world/2", Current.world
    end

    assert_equal "world/1", Current.world
  end

  test "set multiple attributes" do
    Current.world = "world/1"
    Current.account = "account/1"

    Current.set(world: "world/2", account: "account/2") do
      assert_equal "world/2", Current.world
      assert_equal "account/2", Current.account
    end

    assert_equal "world/1", Current.world
    assert_equal "account/1", Current.account
  end

  test "delegation" do
    Current.person = Person.new(42, "David", "Central Time (US & Canada)")
    assert_equal "Central Time (US & Canada)", Current.time_zone
    assert_equal "Central Time (US & Canada)", Current.instance.time_zone
  end

  test "all methods forward to the instance" do
    Current.person = Person.new(42, "David", "Central Time (US & Canada)")
    assert_equal "David, in Central Time (US & Canada)", Current.intro
    assert_equal "David, in Central Time (US & Canada)", Current.instance.intro
  end
end
