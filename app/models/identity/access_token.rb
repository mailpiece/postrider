class Identity::AccessToken < ApplicationRecord
  PREFIXES = { personal: "postrider_pat_", sending: "postrider_" }
  BASE58 = [ *"1".."9", *"A".."H", *"J".."N", *"P".."Z", *"a".."k", *"m".."z" ]
  BODY_LENGTH = 44

  attr_reader :token

  belongs_to :identity

  enum :permission, %w[ read write ].index_by(&:itself), default: :read

  before_validation :assign_token, on: :create

  def self.authenticate(token)
    if token.is_a?(String) && token.present?
      find_by(token_digest: TokenDigester.digest(token))
    end
  end

  def self.generate_token(kind)
    PREFIXES.fetch(kind) + SecureRandom.alphanumeric(BODY_LENGTH, chars: BASE58)
  end

  def allows?(method)
    method.in?(%w[ GET HEAD ]) || write?
  end

  private
    def assign_token
      @token = self.class.generate_token(:personal)
      self.token_digest = TokenDigester.digest(@token)
    end
end
