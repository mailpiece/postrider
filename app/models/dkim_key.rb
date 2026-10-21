require "openssl"
require "base64"

# The RSA key behind a `_domainkey` TXT record: a domain signs its own mail with
# one, the relay seals forwards with its own, and both publish the same shape.
module DkimKey
  SIZE = 2048

  def self.generate
    OpenSSL::PKey::RSA.new(SIZE).to_pem
  end

  def self.load(pem)
    OpenSSL::PKey::RSA.new(pem)
  end

  def self.txt_value(key)
    "v=DKIM1; k=rsa; t=s; h=sha256; p=#{Base64.strict_encode64(key.public_to_der)}"
  end

  # Compared on p= alone: tag order and spacing are the DNS provider's business.
  def self.published_key(record)
    record.to_s[/p=([A-Za-z0-9+\/=]+)/, 1]
  end
end
