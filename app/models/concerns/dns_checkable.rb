module DnsCheckable
  extend ActiveSupport::Concern

  STATUSES = %w[ ok missing invalid ].index_by(&:itself).freeze

  HOSTNAME_UNCONFIGURED = "This relay's hostname isn't configured yet. Set ENV RELAY_HOSTNAME, or BASE_URL".freeze

  included do
    class_attribute :dns_checked_records, default: [], instance_writer: false
  end

  class_methods do
    def checks_dns_records(*records)
      self.dns_checked_records = records
      records.each { |record| enum :"#{record}_status", STATUSES, prefix: record }
    end
  end

  def dns_checked?
    dns_checked_at.present?
  end

  # What's wrong first, in check order, said the way the check said it.
  def dns_error
    dns_checked_records.filter_map { |record| public_send("#{record}_error") }.first
  end

  def check_dns_later
    DnsCheckJob.perform_later(self)
  end

  def check_dns
    check_dns_records
    self.dns_checked_at = Time.current
    save!
    dns_ok?
  end

  private
    def checking(record)
      yield
    rescue DnsResolver::TransientError => error
      assign_attributes "#{record}_error" => error.message
    end

    def set_status(record, status, error = nil)
      assign_attributes "#{record}_status" => status, "#{record}_error" => error
    end

    def relay_hostname
      DnsResolver.normalize(Relay.hostname)
    end

    def relay_mail_domain
      DnsResolver.normalize(Relay.mail_domain)
    end
end
