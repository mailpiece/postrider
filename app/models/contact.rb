class Contact < ApplicationRecord
  belongs_to :account, default: -> { domain.account }
  belongs_to :domain
  has_many :inbound_emails, dependent: :nullify
  has_many :held_inbound_emails, -> { held.ordered }, class_name: "InboundEmail"
  has_many :mailpieces, through: :inbound_emails

  enum :decision, %w[ pending approved denied ].index_by(&:itself), default: :pending

  normalizes :email, with: ->(email) { normalize_email(email) }
  normalizes :name, with: ->(name) { HomographicSpoofing.sanitize_email_name(scrubbed(name)).presence }

  validates :email, presence: true, uniqueness: { scope: :domain_id }

  before_create :assign_number

  scope :ordered, -> { order(created_at: :desc) }
  scope :alphabetically, -> { order(Arel.sql("lower(coalesce(contacts.name, contacts.email))")) }
  scope :matching, ->(query) { where("email LIKE ?", "%#{query}%") }
  scope :preloaded, -> { preload(held_inbound_emails: %i[ events domain ]) }

  # A look-alike address is kept as punycode, so it reads apart from the one it imitates.
  def self.normalize_email(email)
    HomographicSpoofing.sanitize_email_address(scrubbed(email.to_s).strip.downcase)
  end

  # A From with invalid bytes must still file its contact: the gem raises on them.
  def self.scrubbed(string)
    string.dup.force_encoding(Encoding::UTF_8).scrub
  end

  def self.deny_all
    update_all decision: "denied", updated_at: Time.current
  end

  # Flagged is read off the mail, so the senders are picked in Ruby and denied in one statement.
  def self.deny_flagged
    where(id: preloaded.select(&:flagged?).map(&:id)).deny_all
  end

  def self.for_sender(domain, email, name: nil, decision: :pending)
    email = scrubbed(email.to_s)

    if email.present?
      domain.contacts.find_or_create_by(email: email) do |contact|
        contact.name = name
        contact.decision = decision
        contact.lookalike = HomographicSpoofing.email_address_spoof?(email)
      end
    end
  end

  # Writing to someone screens them in. Someone new starts approved, with nothing held to
  # forward; someone screened out stays out until let in by hand.
  def self.screen_in(domain, email)
    if contact = for_sender(domain, email, decision: :approved)
      contact.approve if contact.pending?
    end
  end

  def to_param
    number.to_s
  end

  def title
    name.presence || email
  end

  # A sender's newest held email speaks for them in the Screener.
  def newest_held_email
    held_inbound_emails.first
  end

  def flagged?
    newest_held_email&.spam_check&.flagged?
  end

  def approve
    update! decision: :approved
    forward_held_later
  end

  def deny
    update! decision: :denied
  end

  def forward_held_later
    ForwardHeldJob.perform_later(self)
  end

  def forward_held_now
    inbound_emails.held.find_each(&:forward_held)
  end

  private
    # Numbered per account: contact lists are flat across domains.
    def assign_number
      self.number ||= account.with_lock { account.increment!(:contacts_count).contacts_count }
    end
end
