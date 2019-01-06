# frozen_string_literal: true

class Account < ActiveRecord::Base
  belongs_to :firm, class_name: "Company"
  belongs_to :unautosaved_firm, foreign_key: "firm_id", class_name: "Firm", autosave: false

  alias_attribute :available_credit, :credit_limit

  def self.destroyed_account_ids
    @destroyed_account_ids ||= Hash.new { |h, k| h[k] = [] }
  end

  # Test private kernel method through collection proxy using has_many.
  scope :open, -> { where("firm_name = ?", "37signals") }
  scope :available, -> { open }

  before_destroy do |account|
    if account.firm
      Account.destroyed_account_ids[account.firm.id] << account.id
    end
  end

  validate :check_empty_credit_limit

  private
    def check_empty_credit_limit
      errors.add("credit_limit", :blank) if credit_limit.blank?
    end

    def private_method
      "Sir, yes sir!"
    end
end

class SubAccount < Account
  def self.discriminate_class_for_record(record)
    superclass
  end
  private_class_method :discriminate_class_for_record
end
