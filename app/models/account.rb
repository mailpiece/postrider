class Account < ApplicationRecord
  include Cancellable, MultiTenantable

  has_one :join_code, dependent: :destroy
  has_one :setting, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :domains, dependent: :destroy
  # Through domains only — Account never destroys the mail log; Domain restricts while mail remains.
  has_many :mailboxes, through: :domains
  has_many :sending_tokens, through: :domains
  has_many :mailpieces, through: :domains
  has_many :messages, through: :domains
  has_many :deliveries, through: :domains
  has_many :inbound_emails, through: :domains
  has_many :webhooks, through: :domains
  has_many :suppressions, through: :domains
  has_many :contacts, through: :domains
  has_many :events, through: :domains

  scope :active, -> { where.missing(:cancellation) }

  before_create :assign_external_account_id
  after_create :create_join_code, :create_setting!

  validates :name, presence: true

  class << self
    def create_with_owner(account:, owner:)
      create!(**account).tap do |account|
        account.users.create!(role: :system, name: "System")
        account.users.create!(**owner.with_defaults(role: :owner, verified_at: Time.current))
      end
    end
  end

  def slug
    "/#{AccountSlug.encode(external_account_id)}"
  end

  def account
    self
  end

  def system_user
    users.find_by!(role: :system)
  end

  def active?
    !cancelled?
  end

  private
    def assign_external_account_id
      self.external_account_id ||= ExternalIdSequence.next
    end
end
