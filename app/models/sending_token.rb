class SendingToken < ApplicationRecord
  include Refusable, Tracked

  SMTP_USERNAME = "postrider"

  attr_reader :token

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  has_many :idempotent_requests, dependent: :delete_all

  validates :name, presence: true

  before_validation :assign_token, on: :create

  scope :ordered, -> { order(:created_at) }

  def self.authenticate(token)
    if token.is_a?(String) && token.present?
      find_by(token_digest: TokenDigester.digest(token))
    end
  end

  def authorizes_sending_as?(address)
    if sendable = account.domains.verified.find_by(name: Domain.name_for(address))
      domain == sendable
    else
      false
    end
  end

  def use
    update_column :last_used_at, Time.current
  end

  private
    def assign_token
      @token = Identity::AccessToken.generate_token(:sending)
      self.token_digest = TokenDigester.digest(@token)
    end
end
