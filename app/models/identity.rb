class Identity < ApplicationRecord
  include Joinable, Transferable

  has_passkeys name: :email_address, display_name: -> { Current.user&.name || email_address }

  has_many :access_tokens, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :accounts, through: :users

  before_destroy :deactivate_users, prepend: true

  validates :email_address, format: { with: URI::MailTo::EMAIL_REGEXP }
  normalizes :email_address, with: ->(value) { value.strip.downcase.presence }

  def self.find_by_permissable_access_token(token, method:)
    if (access_token = AccessToken.authenticate(token)) && access_token.allows?(method)
      access_token.identity
    end
  end

  def unclaimed?
    passkeys.none? && users.none?
  end

  private
    def deactivate_users
      users.find_each(&:deactivate)
    end
end
