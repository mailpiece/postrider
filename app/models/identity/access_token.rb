require "openssl"

class Identity::AccessToken < ApplicationRecord
  TOKEN_LENGTH = 24

  attr_reader :token

  belongs_to :identity

  enum :permission, %w[ read write ].index_by(&:itself), default: :read

  before_validation :assign_token, on: :create

  def self.authenticate(token)
    find_by(token_digest: digest(token))
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def allows?(method)
    method.in?(%w[ GET HEAD ]) || write?
  end

  private
    def assign_token
      @token = SecureRandom.alphanumeric(TOKEN_LENGTH)
      self.token_digest = self.class.digest(@token)
    end
end
