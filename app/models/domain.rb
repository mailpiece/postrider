class Domain < ApplicationRecord
  include Accessible
  include Eventable
  include DnsRecords
  include DnsChecks
  include BlockedPhrases
  include AllowedIps
  include Switches

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { creator.account }

  # delete_all: reserved mailboxes guard destroy and must not veto domain teardown.
  has_many :mailboxes, dependent: :delete_all
  has_many :sending_tokens, dependent: :destroy

  # Mail inside the retention window blocks delete; hourly purge frees it. Deliveries follow messages.
  has_many :messages, dependent: :restrict_with_error
  has_many :inbound_emails, dependent: :restrict_with_error
  has_many :deliveries
  has_many :mailpieces
  has_many :webhooks, dependent: :destroy
  has_many :suppressions, dependent: :delete_all
  # destroy so inbound_emails pointing at contacts are nullified first.
  has_many :contacts, dependent: :destroy

  # Domain + its mail's events; deliberately shadows Eventable's narrower has_many :events.
  has_many :events, dependent: :destroy

  enum :catch_all_policy, %w[ disabled discard forward ].index_by(&:itself), default: :disabled

  normalizes :name, with: ->(name) { name.to_s.strip.downcase }

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9.-]+\z/, message: "is not a valid domain" }

  after_create :seed_reserved_mailboxes
  before_destroy :destroy_system_messages, prepend: true

  RESERVED_LOCAL_PARTS = %w[ postmaster dmarc-reports ].freeze

  scope :ordered, -> { order(:name) }
  scope :matching, ->(query) { where("name LIKE ?", "%#{query}%") }
  scope :verified, -> { where(dkim_status: :ok) }
  # Never-checked (nil) domains are unverified too.
  scope :unverified, -> { where.not(dkim_status: :ok).or(where(dkim_status: nil)) }

  def self.accepts?(address)
    if email = EmailAddress.extract(address)
      for_address(email)&.accepts?(email)
    end
  end

  def self.name_for(address)
    if email = EmailAddress.extract(address)
      email.split("@", 2).last.presence&.downcase
    end
  end

  def self.for_address(address)
    if name = name_for(address)
      find_by(name: name)
    end
  end

  def accepts?(email)
    account.active? && verified? && (bounce_address?(email) || (receiving? && (specifically_registered?(email) || discard? || forward?)))
  end

  def specifically_registered?(email)
    local = local_part(email).downcase
    base = local.split("+", 2).first.to_s

    mailboxes.exists?(local_part: [ local, base ].uniq) || base == bounce_local_part
  end

  def webhook_payload(action)
    { domain_id: id, domain: name }
  end

  private
    def eventable_domain
      self
    end

    def seed_reserved_mailboxes
      RESERVED_LOCAL_PARTS.each { |local_part| mailboxes.create!(local_part:) }
    end

    def destroy_system_messages
      messages.system.destroy_all
    end

    def bounce_address?(email)
      local_part(email).split("+", 2).first.to_s.downcase == bounce_local_part
    end

    def bounce_local_part
      local_part(account.setting.bounce_address).split("+", 2).first.to_s.downcase
    end

    def local_part(email)
      EmailAddress.extract(email).to_s.split("@", 2).first.to_s
    end
end
