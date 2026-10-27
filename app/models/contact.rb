class Contact < ApplicationRecord
  belongs_to :account, default: -> { domain.account }
  belongs_to :domain
  has_many :inbound_emails, dependent: :nullify
  has_many :mailpieces, through: :inbound_emails

  enum :decision, %w[ approved denied ].index_by(&:itself), default: :denied

  normalizes :email, with: ->(email) { normalize_email(email) }
  normalizes :name, with: ->(name) { HomographicSpoofing.sanitize_email_name(scrubbed(name)) }

  validates :email, presence: true, uniqueness: { scope: :domain_id }

  before_create :assign_number

  scope :ordered, -> { order(created_at: :desc) }
  scope :matching, ->(query) { where("email LIKE ?", "%#{query}%") }

  # A look-alike address is kept as punycode, so it reads apart from the one it imitates.
  def self.normalize_email(email)
    HomographicSpoofing.sanitize_email_address(scrubbed(email.to_s).strip.downcase)
  end

  # A From with invalid bytes must still file its contact: the gem raises on them.
  def self.scrubbed(string)
    string.dup.force_encoding(Encoding::UTF_8).scrub
  end

  def self.email_counts(contacts)
    Hash.new(0).merge InboundEmail.where(contact: contacts).group(:contact_id).count
  end

  def self.for_sender(domain, email, name: nil)
    email = scrubbed(email.to_s)

    if email.present?
      domain.contacts.find_or_create_by(email: email) do |contact|
        contact.name = name
        contact.lookalike = HomographicSpoofing.email_address_spoof?(email)
      end
    end
  end

  def to_param
    number.to_s
  end

  def title
    name.presence || email
  end

  def mail_state
    denied? ? "held" : "forwarded"
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

  def forward_held
    inbound_emails.held.find_each(&:forward_held)
  end

  private
    # Numbered per account: contact lists are flat across domains.
    def assign_number
      self.number ||= account.with_lock { account.increment!(:contacts_count).contacts_count }
    end
end
