require "socket"
require "logger"
require "ipaddr"

module Relay
  class << self
    def mx_port
      Integer(ENV.fetch("MX_PORT", Rails.env.local? ? 2525 : 25))
    end

    def submission_port
      Integer(ENV.fetch("SUBMISSION_PORT", Rails.env.local? ? 2587 : 587))
    end

    def acme_dns_port
      Integer(ENV.fetch("ACME_DNS_PORT", Rails.env.local? ? 2553 : 53))
    end

    def smtp_log_level
      Logger::Severity.const_get(ENV.fetch("SMTP_LOG_LEVEL", "INFO").upcase)
    rescue NameError
      Logger::INFO
    end

    def bind_address
      ENV.fetch("BIND_ADDRESS", "0.0.0.0")
    end

    # ONCE passes BASE_URL and nothing else, so web and mail on one hostname needs no setting.
    def hostname
      ENV["RELAY_HOSTNAME"].presence || ENV["BASE_URL"].presence&.then { |url| URI.parse(url).host }
    end

    def submission_hostname
      ENV.fetch("SUBMISSION_HOSTNAME") { hostname }
    end

    def tls_hostnames
      [ hostname, submission_hostname ].compact.uniq
    end

    def acme_challenge_names
      tls_hostnames.map { |hostname| "_acme-challenge.#{hostname.downcase.chomp(".")}" }
    end

    def acme_directory
      ENV.fetch("ACME_DIRECTORY", "https://acme-v02.api.letsencrypt.org/directory")
    end

    def acme_contact
      ENV["ACME_CONTACT"]
    end

    def acme?
      hostname.present? && !Rails.env.local?
    end

    def helo_hostname
      ENV.fetch("HELO_HOSTNAME") { hostname }
    end

    def mail_domain
      ENV.fetch("RELAY_MAIL_DOMAIN") { hostname }
    end

    def max_inbound_message_size
      Integer(ENV.fetch("INBOUND_MAX_MESSAGE_SIZE", 25 * 1024 * 1024))
    end

    def max_outbound_message_size
      Integer(ENV.fetch("OUTBOUND_MAX_MESSAGE_SIZE", 10 * 1024 * 1024))
    end

    def retention_period
      Integer(ENV.fetch("RETENTION_DAYS", 30)).days
    end

    def held_retention_period
      Integer(ENV.fetch("HELD_RETENTION_DAYS", 90)).days
    end

    def submission_rate_limit
      Integer(ENV.fetch("SUBMISSION_RATE_LIMIT", 30))
    end

    def mx_max_processings
      Integer(ENV.fetch("MX_MAX_PROCESSINGS", 10))
    end

    def submission_max_processings
      Integer(ENV.fetch("SUBMISSION_MAX_PROCESSINGS", 10))
    end

    def mx_max_connections
      Integer(ENV.fetch("MX_MAX_CONNECTIONS", 50))
    end

    def submission_max_connections
      Integer(ENV.fetch("SUBMISSION_MAX_CONNECTIONS", 50))
    end

    # MX is public; submission already authenticates and rate-limits, so per-IP can be looser.
    def mx_max_connections_per_ip
      Integer(ENV.fetch("MX_MAX_CONNECTIONS_PER_IP", 10))
    end

    def submission_max_connections_per_ip
      Integer(ENV.fetch("SUBMISSION_MAX_CONNECTIONS_PER_IP", 30))
    end

    def mx_max_messages_per_ip
      Integer(ENV.fetch("MX_MAX_MESSAGES_PER_IP", 20))
    end

    def mx_max_tls_sessions_per_ip
      Integer(ENV.fetch("MX_MAX_TLS_SESSIONS_PER_IP", 60))
    end

    def submission_max_tls_sessions_per_ip
      Integer(ENV.fetch("SUBMISSION_MAX_TLS_SESSIONS_PER_IP", 60))
    end

    def submission_max_auth_attempts_per_ip
      Integer(ENV.fetch("SUBMISSION_MAX_AUTH_ATTEMPTS_PER_IP", 60))
    end

    def stress_threshold
      if value = ENV.fetch("STRESS_THRESHOLD", "0.8").presence
        Float(value)
      end
    end

    def mx_max_recipients
      Integer(ENV.fetch("MX_MAX_RECIPIENTS", 50))
    end

    def inbound_storage_limit
      if limit = ENV["INBOUND_STORAGE_LIMIT"].presence
        Integer(limit)
      end
    end

    def outbound_relay
      if relay = ENV["OUTBOUND_RELAY"]
        host, port = relay.split(":")

        if host.present? && port&.match?(/\A\d+\z/)
          [ host, Integer(port) ]
        else
          raise ArgumentError, "OUTBOUND_RELAY must be host:port, got #{relay.inspect}"
        end
      end
    end

    def require_tls_mx_suffixes
      ENV.fetch("REQUIRE_TLS_MX_SUFFIXES", "").split(",").map(&:strip).compact_blank.map { |suffix| mx_suffix(suffix) }
    end

    def mta_sts?
      ENV["MTA_STS"] == "true"
    end

    def sending_ips
      ENV.fetch("SENDING_IPS", "").split(",").map(&:strip).compact_blank.map do |entry|
        name, address, helo = entry.split("=", 3)

        if name.present? && address.present? && helo.present?
          Relay::SendingIp.new(name:, address:, helo:)
        else
          raise ArgumentError, "SENDING_IPS entries must be name=address=helo, got #{entry.inspect}"
        end
      end
    end

    # Without SENDING_IPS, mail leaves from the addresses the relay hostname resolved to at the last DNS check.
    def own_addresses
      if sending_ips.any?
        sending_ips.map(&:address)
      else
        Relay::DnsCheck::Address.pluck(:address)
      end
    end

    def default_sending_ip
      sending_ips.first
    end

    def trusted_proxies
      ENV.fetch("TRUSTED_PROXIES", "").split(",").map(&:strip).compact_blank.map { |proxy| IPAddr.new(proxy) }
    end

    private
      # Leading dot required so "google.com" doesn't also match "notgoogle.com".
      def mx_suffix(suffix)
        suffix = suffix.downcase
        suffix.start_with?(".") ? suffix : ".#{suffix}"
      end
  end
end
