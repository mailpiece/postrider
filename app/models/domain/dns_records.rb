module Domain::DnsRecords
  extend ActiveSupport::Concern

  DKIM_SELECTOR = "postrider".freeze

  DnsRecord = Struct.new(:hostname, :type, :value)

  included do
    encrypts :dkim_private_key

    before_validation :assign_dkim_selector, :generate_dkim_key, on: :create
  end

  def dkim_key
    @dkim_key ||= DkimKey.load(dkim_private_key) if dkim_private_key.present?
  end

  # CNAME alternate to MX left out — basic setup shows one publishable inbound path.
  def dns_records
    [ mx_record, dkim_record ]
  end

  def dns_listings
    [
      DnsCheckable::Listing.new(self, :mx, "Inbound", mx_record),
      DnsCheckable::Listing.new(self, :dkim, "DKIM", dkim_record),
      DnsCheckable::Listing.new(self, :dmarc, "DMARC", dmarc_record),
      DnsCheckable::Listing.new(self, :return_path, "Return-Path", return_path_record)
    ]
  end

  def return_path_enabled?
    verified? && advanced_verified?
  end

  def advanced_verified?
    dmarc_ok? && return_path_ok?
  end

  # MX preferred; CNAME is the alternate (same target) — a name can't carry both.
  def mx_record
    DnsRecord.new(name, "MX", "10 #{Relay.hostname}.")
  end

  def inbound_cname_record
    DnsRecord.new(name, "CNAME", "#{Relay.hostname}.")
  end

  def dkim_record
    DnsRecord.new("#{dkim_selector}._domainkey.#{name}", "TXT", dkim_txt_value)
  end

  def dmarc_record
    DnsRecord.new("_dmarc.#{name}", "TXT", "v=DMARC1; p=none; rua=mailto:dmarc-reports@#{name};")
  end

  def return_path_record
    DnsRecord.new(mailer_host, "CNAME", "#{Relay.mail_domain}.")
  end

  def mailer_host
    "mailer.#{name}"
  end

  private
    def assign_dkim_selector
      self.dkim_selector = DKIM_SELECTOR if dkim_selector.blank?
    end

    def generate_dkim_key
      self.dkim_private_key = DkimKey.generate if dkim_private_key.blank?
    end

    def dkim_txt_value
      DkimKey.txt_value(dkim_key)
    end
end
