class Domain < ApplicationRecord
  include Accessible, DnsRecords, DnsChecks, BlockedPhrases, AllowedIps, Switches

  RESERVED_LOCAL_PARTS = %w[ postmaster dmarc-reports ].freeze

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { creator.account }

  # delete_all: reserved mailboxes guard destroy and must not veto domain teardown.
  has_many :mailboxes, dependent: :delete_all
  has_many :sending_tokens, dependent: :destroy

  # The mail and the events go after the domain, in PurgeMailJob.
  has_many :messages
  has_many :inbound_emails
  has_many :deliveries
  has_many :mailpieces
  has_many :webhooks, dependent: :destroy
  has_many :suppressions, dependent: :delete_all
  has_many :contacts, dependent: :delete_all

  # Its own events and its mail's. They go after the domain, in PurgeMailJob.
  has_many :events

  enum :catch_all_policy, %w[ disabled discard forward ].index_by(&:itself), default: :disabled

  normalizes :name, with: ->(name) { name.to_s.strip.downcase }

  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9.-]+\z/, message: "is not a valid domain" }

  after_create :seed_reserved_mailboxes
  after_destroy_commit :purge_mail_later

  scope :ordered, -> { order(:name) }
  scope :matching, ->(query) { where("name LIKE ?", "%#{query}%") }
  scope :verified, -> { where(dkim_status: :ok) }
  # Never-checked (nil) domains are unverified too.
  scope :unverified, -> { where.not(dkim_status: :ok).or(where(dkim_status: nil)) }

  # The domain row is gone by now, so this takes its id.
  def self.purge_mail_now(domain_id)
    Message.purge Message.where(domain_id:)
    InboundEmail.purge InboundEmail.where(domain_id:)
    Event.purge Event.where(domain_id:)
  end

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
    mailbox_for(email).present? || bounce_address?(email)
  end

  # Its own mailbox, else the one before any +tag.
  def mailbox_for(email)
    mailboxes.where(local_part: local_parts(email)).max_by { |mailbox| mailbox.local_part.length }
  end

  def webhook_payload(action)
    { domain_id: id, domain: name }
  end

  # A domain owns its events rather than being an eventable, so it records its own straight onto them.
  def track_event(action, **particulars)
    events.create!(eventable: self, action: "domain_#{action}", particulars:)
  end

  # Again later for what a delivery or an SMTP session in flight writes after the domain is gone.
  def purge_mail_later
    PurgeMailJob.perform_later(id)
    PurgeMailJob.set(wait: 10.minutes).perform_later(id)
  end

  private
    def seed_reserved_mailboxes
      RESERVED_LOCAL_PARTS.each { |local_part| mailboxes.create!(local_part:) }
    end

    def local_parts(email)
      [ local_part(email).downcase, base_local_part(email) ].uniq
    end

    def bounce_address?(email)
      base_local_part(email) == bounce_local_part
    end

    def bounce_local_part
      base_local_part(account.setting.bounce_address)
    end

    def base_local_part(email)
      local_part(email).split("+", 2).first.to_s.downcase
    end

    def local_part(email)
      EmailAddress.extract(email).to_s.split("@", 2).first.to_s
    end
end
