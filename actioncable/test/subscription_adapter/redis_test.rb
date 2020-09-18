# frozen_string_literal: true

require "test_helper"
require_relative "common"
require_relative "channel_prefix"

require "action_cable/subscription_adapter/redis"

class RedisAdapterTest < ActionCable::TestCase
  include CommonSubscriptionAdapterTest
  include ChannelPrefixTest

  def cable_config
    { adapter: "redis", driver: "ruby" }.tap do |x|
      if host = URI(ENV["REDIS_URL"] || "").hostname
        x[:host] = host
      end
    end
  end
end

class RedisAdapterTest::Hiredis < RedisAdapterTest
  def cable_config
    super.merge(driver: "hiredis")
  end
end

class RedisAdapterTest::AlternateConfiguration < RedisAdapterTest
  def cable_config
    alt_cable_config = super.dup
    alt_cable_config.delete(:url)
    alt_cable_config.merge(host: URI(ENV["REDIS_URL"] || "").hostname || "127.0.0.1", port: 6379, db: 12)
  end
end

class RedisAdapterTest::Connector < ActionCable::TestCase
  test "excludes adapter and channel prefix" do
    config = { url: 1, host: 2, port: 3, db: 4, password: 5, id: "Some custom ID" }

    assert_called_with ::Redis, :new, [ config ] do
      connect config.merge(adapter: "redis", channel_prefix: "custom")
    end
  end

  test "adds default id if it is not specified" do
    config = { url: 1, host: 2, port: 3, db: 4, password: 5, id: "ActionCable-PID-#{$$}" }

    assert_called_with ::Redis, :new, [ config ] do
      connect config.except(:id)
    end
  end

  def connect(config)
    ActionCable::SubscriptionAdapter::Redis.redis_connector.call(config)
  end
end
