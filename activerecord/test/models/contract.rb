# frozen_string_literal: true

class Contract < ActiveRecord::Base
  belongs_to :company
  belongs_to :developer, primary_key: :id
  belongs_to :firm, foreign_key: "company_id"

  attribute :metadata, :json

  before_save :hi, :update_metadata
  after_save :bye

  attr_accessor :hi_count, :bye_count

  def hi
    @hi_count ||= 0
    @hi_count += 1
  end

  def bye
    @bye_count ||= 0
    @bye_count += 1
  end

  def update_metadata
    self.metadata = { company_id: company_id, developer_id: developer_id }
  end
end

class NewContract < Contract
  validates :company_id, presence: true
end
