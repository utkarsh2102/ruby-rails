class Book < ActiveRecord::Base
  has_many :authors

  has_many :citations, :foreign_key => 'book1_id'
  has_many :references, -> { distinct }, through: :citations, source: :reference_of

  has_many :subscriptions
  has_many :subscribers, through: :subscriptions

  enum status: [:proposed, :written, :published]
  enum read_status: {unread: 0, reading: 2, read: 3}
  enum nullable_status: [:single, :married]

  def published!
    super
    "do publish work..."
  end
end
