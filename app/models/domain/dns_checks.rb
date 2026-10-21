module Domain::DnsChecks
  extend ActiveSupport::Concern
  include DnsCheckable

  included do
    checks_dns_records :mx, :dkim, :dmarc, :return_path

    after_update :track_verification_change, if: :saved_change_to_dkim_status?
  end

  class_methods do
    def check_dns_all_later
      find_each(&:check_dns_later)
    end
  end

  def dns_ok?
    mx_ok? && dkim_ok?
  end

  def verified?
    dkim_ok?
  end

  private
    def check_dns_records
      checking(:mx) { check_mx_record }
      checking(:dkim) { check_dkim_record }
      checking(:dmarc) { check_dmarc_record }
      checking(:return_path) { check_return_path_record }
    end

    def check_mx_record
      if Relay.hostname.blank?
        set_status :mx, :invalid, DnsCheckable::HOSTNAME_UNCONFIGURED
      else
        mx_hosts = DnsResolver.mx(name)
        cname_targets = DnsResolver.cname(name)

        if mx_hosts.include?(relay_hostname) || cname_targets.include?(relay_hostname)
          set_status :mx, :ok
        elsif mx_hosts.empty? && cname_targets.empty?
          set_status :mx, :missing, "No MX or CNAME record points #{name} at #{Relay.hostname}"
        elsif cname_targets.any?
          set_status :mx, :invalid, "A CNAME record exists at #{name} but doesn't point to #{Relay.hostname}"
        else
          set_status :mx, :invalid, "MX records exist but none point to #{Relay.hostname}"
        end
      end
    end

    def check_dkim_record
      host = "#{dkim_selector}._domainkey.#{name}"
      records = DnsResolver.txt(host)

      if records.empty?
        set_status :dkim, :missing, "No DKIM record exists at #{host}"
      elsif records.size > 1
        set_status :dkim, :invalid, "There are #{records.size} records at #{host}; there should be exactly one"
      elsif dkim_key_matches?(records.first)
        set_status :dkim, :ok
      else
        set_status :dkim, :invalid, "The DKIM record at #{host} doesn't match the value we generated"
      end
    end

    def dkim_key_matches?(published)
      DkimKey.published_key(published) == DkimKey.published_key(dkim_record.value)
    end

    def check_dmarc_record
      host = "_dmarc.#{name}"
      records = DnsResolver.txt(host).grep(/\Av=DMARC1/i)

      if records.empty?
        set_status :dmarc, :missing, "No DMARC record exists at #{host}"
      elsif records.any? { |record| record.match?(/\bp=/i) }
        set_status :dmarc, :ok
      else
        set_status :dmarc, :invalid, "A DMARC record exists at #{host} but has no policy (p=) tag"
      end
    end

    def check_return_path_record
      if Relay.mail_domain.blank?
        set_status :return_path, :invalid, DnsCheckable::HOSTNAME_UNCONFIGURED
      else
        targets = DnsResolver.cname(mailer_host)

        if targets.empty?
          set_status :return_path, :missing, "No CNAME record exists at #{mailer_host}"
        elsif targets.include?(relay_mail_domain)
          set_status :return_path, :ok
        else
          set_status :return_path, :invalid, "A CNAME record exists at #{mailer_host} but doesn't point to #{Relay.mail_domain}"
        end
      end
    end

    def track_verification_change
      if verified?
        track_event "verified"
      elsif previously_verified?
        track_event "verification_lost", status: dkim_status, error: dkim_error
      end
    end

    def previously_verified?
      dkim_status_previously_was == self.class.dkim_statuses[:ok]
    end
end
