require "mailauth"

# The relay's own signing key. A forward's From: is a third party's, so all we can
# honestly sign is what we concluded about it: an ARC set under our name (RFC 8617 §5.1).
class Relay::SealingKey < ApplicationRecord
  self.table_name = "relay_sealing_keys"

  SINGLETON_GUARD = 0
  SELECTOR = "arc".freeze

  # Sealing oversigns nothing by default; ask for the same list our outbound DKIM
  # signs under, so a header added downstream breaks the message signature.
  OVERSIGNED_HEADERS = MailAuth::Dkim::Signer::OVERSIGNED_HEADERS

  encrypts :private_key

  validates :singleton_guard, inclusion: { in: [ SINGLETON_GUARD ] }

  before_validation :generate_private_key, on: :create

  def self.instance
    first_or_create!
  rescue ActiveRecord::RecordNotUnique
    first
  end

  # `chain_status` is what the chain arrived as: a sealer records a verdict, never reaches one.
  def seal(raw, authentication_results:, chain_status:)
    if sealable?
      MailAuth::Arc.seal(raw, authentication_results: authentication_results, chain_status: chain_status,
        domain: Relay.mail_domain, selector: SELECTOR, key: key, oversign: OVERSIGNED_HEADERS)
    else
      raw
    end
  end

  # A set nobody can fetch the key for fails the whole chain (RFC 8617 §5.2), taking
  # every earlier hop's with it — so an unpublished key seals nothing at all.
  def sealable?
    Relay.mail_domain.present? && Relay::DnsCheck.instance.sealing_key_ok?
  end

  def key
    @key ||= DkimKey.load(private_key) if private_key.present?
  end

  def dns_record
    Domain::DnsRecords::DnsRecord.new(host, "TXT", txt_value)
  end

  def host
    "#{SELECTOR}._domainkey.#{Relay.mail_domain}"
  end

  def txt_value
    DkimKey.txt_value(key)
  end

  private
    def generate_private_key
      self.private_key = DkimKey.generate if private_key.blank?
    end
end
