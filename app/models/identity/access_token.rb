require "openssl"

class Identity::AccessToken < ApplicationRecord
  PREFIXES = { personal: "postrider_pat_", sending: "postrider_" }
  BASE58 = [ *"1".."9", *"A".."H", *"J".."N", *"P".."Z", *"a".."k", *"m".."z" ]
  BODY_LENGTH = 44

  attr_reader :token

  belongs_to :identity

  enum :permission, %w[ read write ].index_by(&:itself), default: :read

  before_validation :assign_token, on: :create

  def self.authenticate(token)
    find_by(token_digest: digest(token))
  end

  def self.generate_token(kind)
    PREFIXES.fetch(kind) + SecureRandom.alphanumeric(BODY_LENGTH, chars: BASE58)
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def allows?(method)
    method.in?(%w[ GET HEAD ]) || write?
  end

  private
    def assign_token
      @token = self.class.generate_token(:personal)
      self.token_digest = self.class.digest(@token)
    end
end
