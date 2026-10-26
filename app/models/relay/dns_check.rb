class Relay::DnsCheck < ApplicationRecord
  include DnsCheckable

  self.table_name = "relay_dns_checks"

  SINGLETON_GUARD = 0
  PUBLIC_IP_PLACEHOLDER = "this server's public IP".freeze

  # A record to publish, with what it is for and the check that looks at it, if one does.
  DnsRecord = Struct.new(:purpose, :check, :hostname, :type, :value)

  checks_dns_records :address, :ptr, :spf, :submission_address, :mail_domain, :sealing_key, :acme_delegation

  has_many :addresses, class_name: "Relay::DnsCheck::Address", foreign_key: :relay_dns_check_id, dependent: :delete_all, inverse_of: :relay_dns_check

  validates :singleton_guard, inclusion: { in: [ SINGLETON_GUARD ] }

  def self.instance
    first_or_create!
  rescue ActiveRecord::RecordNotUnique
    first
  end

  def check_dns
    transaction { super }
  end

  # The sealing key and the ACME delegation are reported, not gated on: unpublished,
  # one only degrades forwarding and the other only certificate renewal, and gating
  # would flip every existing relay to "not ready" on upgrade.
  def dns_ok?
    relay_dns_ok? && submission_dns_ok? && mail_domain_dns_ok?
  end

  # Distinct submission hostname needs its own A/AAAA for clients to reach it.
  def own_submission_hostname?
    Relay.submission_hostname.present? && Relay.submission_hostname != Relay.hostname
  end

  # Distinct mail domain needs its own A/AAAA, or every mailer.<domain> CNAME dead-ends.
  def own_mail_domain?
    Relay.mail_domain.present? && Relay.mail_domain != Relay.hostname
  end

  def dns_records
    [
      DnsRecord.new("Relay hostname", :address, Relay.hostname, "A/AAAA", public_ip_display),
      *mail_domain_records,
      *ptr_records,
      DnsRecord.new("SPF", :spf, Relay.mail_domain, "TXT", expected_spf_value),
      DnsRecord.new("ARC sealing key", :sealing_key, sealing_key.host, "TXT", sealing_key.txt_value),
      *submission_records,
      *acme_delegation_records
    ]
  end

  def dns_listings
    dns_records.map { |record| DnsCheckable::Listing.new(self, record.check, record.purpose, record) }
  end

  # Let's Encrypt asks the relay itself for its challenge record, so each challenge
  # name is delegated to this host by NS, one per name the certificate covers.
  def acme_delegation_records
    Relay.acme_challenge_names.map do |name|
      DnsRecord.new("Certificate challenge", :acme_delegation, name, "NS", "#{Relay.hostname}.")
    end
  end

  private
    def relay_dns_ok?
      address_ok? && ptr_ok? && spf_ok?
    end

    def submission_dns_ok?
      if own_submission_hostname?
        submission_address_ok?
      else
        true
      end
    end

    def mail_domain_dns_ok?
      if own_mail_domain?
        mail_domain_ok?
      else
        true
      end
    end

    def check_dns_records
      checking(:address) do
        check_address_record
        checking(:ptr) { check_ptr_record }
      end
      checking(:spf) { check_spf_record }
      checking(:submission_address) { check_submission_address_record }
      checking(:mail_domain) { check_mail_domain_record }
      checking(:sealing_key) { check_sealing_key_record }
      checking(:acme_delegation) { check_acme_delegation_record }
    end

    def check_address_record
      if Relay.hostname.blank?
        self.addresses = []
        set_status :address, :invalid, HOSTNAME_UNCONFIGURED
      else
        self.addresses = DnsResolver.addresses(Relay.hostname).map { |address| Address.new(address: address, expected_ptr_hostname: relay_hostname) }

        if addresses.any?
          set_status :address, :ok
        else
          set_status :address, :missing, "No A/AAAA record yet for #{Relay.hostname}"
        end
      end
    end

    def check_ptr_record
      if addresses.empty?
        set_status :ptr, :invalid, "Can't check PTR until #{Relay.hostname.presence || "the hostname"} resolves to an address"
      else
        addresses.each { |address| address.update!(ptr_hostname: DnsResolver.name(address.address)) }

        if addresses.all? { |address| address.ptr_hostname.blank? }
          set_status :ptr, :missing, "No PTR record for #{addresses.map(&:address).to_sentence}"
        elsif ptr_matches_hostname?
          set_status :ptr, :ok
        else
          set_status :ptr, :invalid, mismatched_ptr_message
        end
      end
    end

    def ptr_matches_hostname?
      addresses.all?(&:ptr_matches_expected_hostname?)
    end

    def mismatched_ptr_message
      mismatches = addresses.reject(&:ptr_matches_expected_hostname?)
      descriptions = mismatches.map { |address| "#{address.address} → #{address.ptr_hostname.presence || "no PTR"} (expected #{address.expected_ptr_hostname})" }
      "PTR mismatch: #{descriptions.to_sentence}"
    end

    # Return-Paths resolve to the mail domain, so that's the name receivers evaluate SPF against.
    def check_spf_record
      if Relay.mail_domain.blank?
        set_status :spf, :invalid, HOSTNAME_UNCONFIGURED
      elsif (published = published_spf_record).nil?
        set_status :spf, :missing, "Publish #{expected_spf_value} at #{Relay.mail_domain}"
      elsif spf_authorizes_us?(published)
        set_status :spf, :ok
      else
        set_status :spf, :invalid, "SPF at #{Relay.mail_domain} doesn't include #{spf_mechanism}"
      end
    end

    def published_spf_record
      DnsResolver.txt(Relay.mail_domain).find { |record| record.match?(/\Av=spf1\b/i) }
    end

    def spf_authorizes_us?(published)
      published.split.map(&:downcase).include?(spf_mechanism.downcase)
    end

    def expected_spf_value
      "v=spf1 #{spf_mechanism} -all"
    end

    def spf_mechanism
      "a:#{Relay.mail_domain}"
    end

    def check_submission_address_record
      if own_submission_hostname?
        check_submission_addresses DnsResolver.addresses(Relay.submission_hostname)
      else
        set_status :submission_address, nil
      end
    end

    def check_submission_addresses(submission_addresses)
      if submission_addresses.empty?
        set_status :submission_address, :missing, "No A/AAAA record yet for #{Relay.submission_hostname}"
      elsif points_here?(submission_addresses)
        set_status :submission_address, :ok
      else
        set_status :submission_address, :invalid, "#{Relay.submission_hostname} resolves to #{submission_addresses.to_sentence}, not this server"
      end
    end

    # Until the relay hostname resolves, any resolution is enough; then require a shared address.
    def points_here?(submission_addresses)
      addresses.empty? || submission_addresses.intersect?(addresses.map(&:address))
    end

    # Its A/AAAA is what the SPF a: mechanism authorizes; its MX is what brings VERP bounces home.
    def check_mail_domain_record
      if own_mail_domain?
        check_mail_domain_addresses DnsResolver.addresses(Relay.mail_domain)
      else
        set_status :mail_domain, nil
      end
    end

    def check_mail_domain_addresses(mail_addresses)
      if mail_addresses.empty?
        set_status :mail_domain, :missing, "No A/AAAA record yet for #{Relay.mail_domain}"
      elsif points_here?(mail_addresses)
        check_mail_domain_exchangers DnsResolver.mx(Relay.mail_domain)
      else
        set_status :mail_domain, :invalid, "#{Relay.mail_domain} resolves to #{mail_addresses.to_sentence}, not this server"
      end
    end

    def check_mail_domain_exchangers(exchangers)
      if exchangers.empty?
        set_status :mail_domain, :missing, "No MX record yet for #{Relay.mail_domain} — bounces have nowhere to land"
      elsif exchangers.include?(relay_hostname)
        set_status :mail_domain, :ok
      else
        set_status :mail_domain, :invalid, "MX at #{Relay.mail_domain} points to #{exchangers.to_sentence}, not #{Relay.hostname}"
      end
    end

    # Forwards carry an ARC seal from this key; unpublished, no receiver can read it.
    def check_sealing_key_record
      if Relay.mail_domain.blank?
        set_status :sealing_key, :invalid, HOSTNAME_UNCONFIGURED
      else
        check_sealing_keys DnsResolver.txt(sealing_key.host)
      end
    end

    def check_sealing_keys(records)
      if records.empty?
        set_status :sealing_key, :missing, "No ARC sealing key published at #{sealing_key.host}"
      elsif records.size > 1
        set_status :sealing_key, :invalid, "There are #{records.size} records at #{sealing_key.host}; there should be exactly one"
      elsif DkimKey.published_key(records.first) == DkimKey.published_key(sealing_key.txt_value)
        set_status :sealing_key, :ok
      else
        set_status :sealing_key, :invalid, "The record at #{sealing_key.host} doesn't match the key we seal forwards with"
      end
    end

    def sealing_key
      @sealing_key ||= Relay::SealingKey.instance
    end

    # Only an install that orders its own certificate needs the delegation.
    def check_acme_delegation_record
      if Relay.acme?
        check_acme_delegations acme_delegation_records.map(&:hostname).index_with { |name| DnsResolver.ns(name) }
      else
        set_status :acme_delegation, nil
      end
    end

    def check_acme_delegations(nameservers)
      if (undelegated = nameservers.select { |_, servers| servers.empty? }).any?
        set_status :acme_delegation, :missing, "No NS record yet for #{undelegated.keys.to_sentence}"
      elsif (elsewhere = nameservers.reject { |_, servers| servers.include?(relay_hostname) }).any?
        set_status :acme_delegation, :invalid, elsewhere.map { |name, servers| "#{name} is delegated to #{servers.to_sentence}, not #{Relay.hostname}" }.to_sentence
      else
        set_status :acme_delegation, :ok
      end
    end

    # One mail_domain status answers for both records, and only a distinct mail domain is checked.
    def mail_domain_records
      if own_mail_domain?
        [
          DnsRecord.new("Mail domain", :mail_domain, Relay.mail_domain, "A/AAAA", public_ip_display),
          DnsRecord.new("Bounces", :mail_domain, Relay.mail_domain, "MX", "10 #{Relay.hostname}.")
        ]
      else
        [ DnsRecord.new("Bounces", nil, Relay.mail_domain, "MX", "10 #{Relay.hostname}.") ]
      end
    end

    def submission_records
      if own_submission_hostname?
        [ DnsRecord.new("Submission hostname", :submission_address, Relay.submission_hostname, "A/AAAA", public_ip_display) ]
      else
        []
      end
    end

    def public_ip_display
      addresses.any? ? addresses.map(&:address).to_sentence : PUBLIC_IP_PLACEHOLDER
    end

    # One PTR per address; placeholder row keeps the shape visible before resolve.
    def ptr_records
      if addresses.any?
        addresses.map { |address| DnsRecord.new("Reverse DNS", :ptr, address.address, "PTR", "#{Relay.hostname}.") }
      else
        [ DnsRecord.new("Reverse DNS", :ptr, PUBLIC_IP_PLACEHOLDER, "PTR", "#{Relay.hostname}.") ]
      end
    end
end
