# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/channel/channel_generator"

class ChannelGeneratorTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  tests Rails::Generators::ChannelGenerator

  def test_application_cable_skeleton_is_created
    run_generator ["books"]

    assert_file "app/channels/application_cable/channel.rb" do |cable|
      assert_match(/module ApplicationCable\n  class Channel < ActionCable::Channel::Base\n/, cable)
    end

    assert_file "app/channels/application_cable/connection.rb" do |cable|
      assert_match(/module ApplicationCable\n  class Connection < ActionCable::Connection::Base\n/, cable)
    end
  end

  def test_channel_is_created
    run_generator ["chat"]

    assert_file "app/channels/chat_channel.rb" do |channel|
      assert_match(/class ChatChannel < ApplicationCable::Channel/, channel)
    end

    assert_file "app/javascript/channels/chat_channel.js" do |channel|
      assert_match(/import consumer from "\.\/consumer"\s+consumer\.subscriptions\.create\("ChatChannel/, channel)
    end
  end

  def test_channel_with_multiple_actions_is_created
    run_generator ["chat", "speak", "mute"]

    assert_file "app/channels/chat_channel.rb" do |channel|
      assert_match(/class ChatChannel < ApplicationCable::Channel/, channel)
      assert_match(/def speak/, channel)
      assert_match(/def mute/, channel)
    end

    assert_file "app/javascript/channels/chat_channel.js" do |channel|
      assert_match(/import consumer from "\.\/consumer"\s+consumer\.subscriptions\.create\("ChatChannel/, channel)
      assert_match(/,\n\n  speak/, channel)
      assert_match(/,\n\n  mute: function\(\) \{\n    return this\.perform\('mute'\);\n  \}\n\}\);/, channel)
    end
  end

  def test_channel_asset_is_not_created_when_skip_assets_is_passed
    run_generator ["chat", "--skip-assets"]

    assert_file "app/channels/chat_channel.rb" do |channel|
      assert_match(/class ChatChannel < ApplicationCable::Channel/, channel)
    end

    assert_no_file "app/javascript/channels/chat_channel.js"
  end

  def test_consumer_js_is_created_if_not_present_already
    run_generator ["chat"]
    FileUtils.rm("#{destination_root}/app/javascript/channels/index.js")
    FileUtils.rm("#{destination_root}/app/javascript/channels/consumer.js")
    run_generator ["camp"]

    assert_file "app/javascript/channels/index.js"
    assert_file "app/javascript/channels/consumer.js"
  end

  def test_invokes_default_test_framework
    run_generator %w(chat -t=test_unit)

    assert_file "test/channels/chat_channel_test.rb" do |test|
      assert_match(/class ChatChannelTest < ActionCable::Channel::TestCase/, test)
      assert_match(/# test "subscribes" do/, test)
      assert_match(/#   assert subscription.confirmed\?/, test)
    end
  end

  def test_channel_on_revoke
    run_generator ["chat"]
    run_generator ["chat"], behavior: :revoke

    assert_no_file "app/channels/chat_channel.rb"
    assert_no_file "app/javascript/channels/chat_channel.js"
    assert_no_file "test/channels/chat_channel_test.rb"

    assert_file "app/channels/application_cable/channel.rb"
    assert_file "app/channels/application_cable/connection.rb"
    assert_file "app/javascript/channels/index.js"
    assert_file "app/javascript/channels/consumer.js"
  end

  def test_channel_suffix_is_not_duplicated
    run_generator ["chat_channel"]

    assert_no_file "app/channels/chat_channel_channel.rb"
    assert_file "app/channels/chat_channel.rb"

    assert_no_file "app/javascript/channels/chat_channel_channel.js"
    assert_file "app/javascript/channels/chat_channel.js"

    assert_no_file "test/channels/chat_channel_channel_test.rb"
    assert_file "test/channels/chat_channel_test.rb"
  end
end
