require "openssl"

module TokenDigester
  extend self

  class MissingPepper < StandardError; end

  MINIMUM_PEPPER_LENGTH = 32

  def digest(raw)
    OpenSSL::HMAC.hexdigest("SHA256", pepper, raw)
  end

  def verify_pepper!
    pepper
    true
  end

  private
    def pepper
      @pepper ||= configured_pepper(ENV["OAUTH_TOKEN_PEPPER"])
    end

    def configured_pepper(value)
      if value.blank?
        Rails.application.key_generator.generate_key("token_digest_pepper", 32)
      elsif value.length < MINIMUM_PEPPER_LENGTH
        raise MissingPepper, "OAUTH_TOKEN_PEPPER must be at least #{MINIMUM_PEPPER_LENGTH} characters; generate one with bin/rails secret"
      else
        value
      end
    end
end
