# A msg-id the submitter wrote. Clients thread replies by the IDs they set, so we keep them,
# except one whose host names a machine rather than a public domain: that would leak the
# hostname, so it gets a stand-in at the sending domain. The stand-in is derived from the
# original, so the sender's later In-Reply-To and References can land on the ID recipients saw.
class SmtpSubmission::MessageId
  FORMAT = /<([^<>@\s]+)@([^<>@\s]+)>/

  # Reserved for home networks by RFC 8375, yet under .arpa, which the public suffix list passes.
  HOME_NETWORK_SUFFIX = ".home.arpa"

  class << self
    def parse(value)
      if match = value.to_s.strip.match(/\A#{FORMAT}\z/)
        new(*match.captures)
      end
    end

    def well_formed?(value)
      parse(value).present?
    end

    # Derived from SECRET_KEY_BASE: rotating it changes every stand-in, so replies to mail
    # sent before no longer match the IDs their recipients saw.
    def key
      @key ||= Rails.application.key_generator.generate_key("message_id_rewrite", 32)
    end
  end

  def initialize(local, host)
    @local, @host = local, host
  end

  def at(domain)
    machine_host? ? stand_in_at(domain) : to_s
  end

  def machine_host?
    name = @host.downcase.delete_suffix(".")
    !name.include?(".") || ip_literal?(name) || name.end_with?(HOME_NETWORK_SUFFIX) || !public_domain?(name)
  end

  def stand_in_at(domain)
    "<#{stand_in}@#{domain}>"
  end

  def to_s
    "<#{@local}@#{@host}>"
  end

  private
    def ip_literal?(name)
      name.start_with?("[") || name.match?(Resolv::AddressRegex)
    end

    def public_domain?(name)
      PublicSuffix.valid?(name, default_rule: nil)
    end

    # Domains are case-insensitive, so a reference typed with another case still matches.
    def stand_in
      OpenSSL::HMAC.hexdigest("SHA256", self.class.key, "<#{@local}@#{@host.downcase}>").first(32)
    end
end
