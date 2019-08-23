# frozen_string_literal: true

require_relative "../../test_helper"

module MailExt
  class RecipientsTest < ActiveSupport::TestCase
    setup do
      @mail = Mail.new \
        to: "david@basecamp.com",
        cc: "jason@basecamp.com",
        bcc: "andrea@basecamp.com",
        x_original_to: "ryan@basecamp.com"
    end

    test "recipients include everyone from to, cc, bcc, and x-original-to" do
      assert_equal %w[ david@basecamp.com jason@basecamp.com andrea@basecamp.com ryan@basecamp.com ], @mail.recipients
    end

    test "recipients addresses use address objects" do
      assert_equal "basecamp.com", @mail.recipients_addresses.first.domain
    end

    test "to addresses use address objects" do
      assert_equal "basecamp.com", @mail.to_addresses.first.domain
    end

    test "cc addresses use address objects" do
      assert_equal "basecamp.com", @mail.cc_addresses.first.domain
    end

    test "bcc addresses use address objects" do
      assert_equal "basecamp.com", @mail.bcc_addresses.first.domain
    end
  end
end
