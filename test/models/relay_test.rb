require "test_helper"

class RelayTest < ActiveSupport::TestCase
  test "hostname reads RELAY_HOSTNAME" do
    with_env(RELAY_HOSTNAME: "mx.example", BASE_URL: "https://app.example") do
      assert_equal "mx.example", Relay.hostname
    end
  end

  test "hostname falls back to the host of BASE_URL when RELAY_HOSTNAME is blank" do
    with_env(RELAY_HOSTNAME: "", BASE_URL: "https://app.example:8443/") do
      assert_equal "app.example", Relay.hostname
    end
  end

  test "hostname is nil when neither RELAY_HOSTNAME nor BASE_URL is set" do
    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil) do
      assert_nil Relay.hostname
    end
  end

  test "submission_hostname defaults to hostname when unset" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: nil) do
      assert_equal "mx.example", Relay.submission_hostname
    end
  end

  test "submission_hostname uses SUBMISSION_HOSTNAME when set" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: "smtp.example") do
      assert_equal "smtp.example", Relay.submission_hostname
    end
  end

  test "mx_port and submission_port default to 2525 and 2587 locally, 25 and 587 elsewhere, and read MX_PORT and SUBMISSION_PORT" do
    with_env(MX_PORT: nil, SUBMISSION_PORT: nil) do
      assert_equal [ 2525, 2587 ], [ Relay.mx_port, Relay.submission_port ]

      Rails.env.stubs(:local?).returns(false)
      assert_equal [ 25, 587 ], [ Relay.mx_port, Relay.submission_port ]
    end

    with_env(MX_PORT: 1025, SUBMISSION_PORT: 1587) do
      assert_equal [ 1025, 1587 ], [ Relay.mx_port, Relay.submission_port ]
    end
  end

  test "acme_dns_port defaults to 2553 locally, 53 elsewhere, and reads ACME_DNS_PORT" do
    with_env(ACME_DNS_PORT: nil) do
      assert_equal 2553, Relay.acme_dns_port

      Rails.env.stubs(:local?).returns(false)
      assert_equal 53, Relay.acme_dns_port
    end

    with_env(ACME_DNS_PORT: 15353) do
      assert_equal 15353, Relay.acme_dns_port
    end
  end

  test "smtp_log_level defaults to INFO when unset" do
    with_env(SMTP_LOG_LEVEL: nil) do
      assert_equal Logger::INFO, Relay.smtp_log_level
    end
  end

  test "smtp_log_level reads SMTP_LOG_LEVEL case-insensitively" do
    with_env(SMTP_LOG_LEVEL: "debug") do
      assert_equal Logger::DEBUG, Relay.smtp_log_level
    end
  end

  test "smtp_log_level falls back to INFO for an unknown level" do
    with_env(SMTP_LOG_LEVEL: "verbose") do
      assert_equal Logger::INFO, Relay.smtp_log_level
    end
  end

  test "tls_hostnames lists hostname and submission_hostname without duplicates" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: "smtp.example") do
      assert_equal [ "mx.example", "smtp.example" ], Relay.tls_hostnames
    end
  end

  test "tls_hostnames collapses to one entry when SUBMISSION_HOSTNAME isn't set" do
    with_env(RELAY_HOSTNAME: "mx.example", SUBMISSION_HOSTNAME: nil) do
      assert_equal [ "mx.example" ], Relay.tls_hostnames
    end
  end

  test "outbound_relay parses host:port" do
    with_env(OUTBOUND_RELAY: "relay.example:2525") do
      assert_equal [ "relay.example", 2525 ], Relay.outbound_relay
    end
  end

  test "outbound_relay raises when the port is missing" do
    with_env(OUTBOUND_RELAY: "relay.example") do
      assert_raises(ArgumentError) { Relay.outbound_relay }
    end
  end

  test "outbound_relay raises when the port is not a number" do
    with_env(OUTBOUND_RELAY: "relay.example:smtp") do
      assert_raises(ArgumentError) { Relay.outbound_relay }
    end
  end

  test "retention_period defaults to 30 days" do
    with_env(RETENTION_DAYS: nil) do
      assert_equal 30.days, Relay.retention_period
    end
  end

  test "retention_period reads RETENTION_DAYS" do
    with_env(RETENTION_DAYS: 7) do
      assert_equal 7.days, Relay.retention_period
    end
  end

  test "slow_down_pause_period defaults to 60 minutes and reads SLOW_DOWN_PAUSE_MINUTES" do
    with_env(SLOW_DOWN_PAUSE_MINUTES: nil) do
      assert_equal 60.minutes, Relay.slow_down_pause_period
    end

    with_env(SLOW_DOWN_PAUSE_MINUTES: 15) do
      assert_equal 15.minutes, Relay.slow_down_pause_period
    end
  end

  test "max_inbound_message_size defaults to 25 MB and reads INBOUND_MAX_MESSAGE_SIZE" do
    with_env(INBOUND_MAX_MESSAGE_SIZE: nil) do
      assert_equal 25 * 1024 * 1024, Relay.max_inbound_message_size
    end

    with_env(INBOUND_MAX_MESSAGE_SIZE: 40.megabytes) do
      assert_equal 40.megabytes, Relay.max_inbound_message_size
    end
  end

  test "max_outbound_message_size defaults to 10 MB and reads OUTBOUND_MAX_MESSAGE_SIZE independently of the inbound limit" do
    with_env(OUTBOUND_MAX_MESSAGE_SIZE: nil, INBOUND_MAX_MESSAGE_SIZE: 40.megabytes) do
      assert_equal 10 * 1024 * 1024, Relay.max_outbound_message_size
    end

    with_env(OUTBOUND_MAX_MESSAGE_SIZE: 5.megabytes, INBOUND_MAX_MESSAGE_SIZE: 40.megabytes) do
      assert_equal 5.megabytes, Relay.max_outbound_message_size
    end
  end

  test "per-IP rate limits default to 20 messages, 60 TLS sessions and 60 AUTH attempts a minute, and read their variables" do
    with_env(MX_MAX_MESSAGES_PER_IP: nil, MX_MAX_TLS_SESSIONS_PER_IP: nil, SUBMISSION_MAX_TLS_SESSIONS_PER_IP: nil, SUBMISSION_MAX_AUTH_ATTEMPTS_PER_IP: nil) do
      assert_equal 20, Relay.mx_max_messages_per_ip
      assert_equal 60, Relay.mx_max_tls_sessions_per_ip
      assert_equal 60, Relay.submission_max_tls_sessions_per_ip
      assert_equal 60, Relay.submission_max_auth_attempts_per_ip
    end

    with_env(MX_MAX_MESSAGES_PER_IP: 5, MX_MAX_TLS_SESSIONS_PER_IP: 6, SUBMISSION_MAX_TLS_SESSIONS_PER_IP: 7, SUBMISSION_MAX_AUTH_ATTEMPTS_PER_IP: 8) do
      assert_equal 5, Relay.mx_max_messages_per_ip
      assert_equal 6, Relay.mx_max_tls_sessions_per_ip
      assert_equal 7, Relay.submission_max_tls_sessions_per_ip
      assert_equal 8, Relay.submission_max_auth_attempts_per_ip
    end
  end

  test "bulk_messages_per_hour defaults to 120 for Outlook.com and Yahoo and 1800 elsewhere, and reads their variables" do
    with_env(BULK_OUTLOOK_MESSAGES_PER_HOUR: nil, BULK_YAHOO_MESSAGES_PER_HOUR: nil, BULK_GMAIL_MESSAGES_PER_HOUR: nil, BULK_OTHER_MESSAGES_PER_HOUR: nil) do
      assert_equal 120, Relay.bulk_messages_per_hour("outlook")
      assert_equal 120, Relay.bulk_messages_per_hour("yahoo")
      assert_equal 1800, Relay.bulk_messages_per_hour("gmail")
      assert_equal 1800, Relay.bulk_messages_per_hour("example.com")
    end

    with_env(BULK_OUTLOOK_MESSAGES_PER_HOUR: 2, BULK_YAHOO_MESSAGES_PER_HOUR: 3, BULK_GMAIL_MESSAGES_PER_HOUR: 4, BULK_OTHER_MESSAGES_PER_HOUR: 5) do
      assert_equal 2, Relay.bulk_messages_per_hour("outlook")
      assert_equal 3, Relay.bulk_messages_per_hour("yahoo")
      assert_equal 4, Relay.bulk_messages_per_hour("gmail")
      assert_equal 5, Relay.bulk_messages_per_hour("example.com")
    end
  end

  test "stress_threshold defaults to 0.8 and reads STRESS_THRESHOLD as a Float" do
    with_env(STRESS_THRESHOLD: nil) do
      assert_equal 0.8, Relay.stress_threshold
    end

    with_env(STRESS_THRESHOLD: "0.5") do
      assert_equal 0.5, Relay.stress_threshold
    end

    with_env(STRESS_THRESHOLD: "") do
      assert_nil Relay.stress_threshold
    end
  end

  test "inbound_storage_limit is nil when INBOUND_STORAGE_LIMIT is unset and reads it in bytes" do
    with_env(INBOUND_STORAGE_LIMIT: nil) do
      assert_nil Relay.inbound_storage_limit
    end

    with_env(INBOUND_STORAGE_LIMIT: 5.gigabytes) do
      assert_equal 5.gigabytes, Relay.inbound_storage_limit
    end
  end

  test "trusted_proxies is empty when TRUSTED_PROXIES is unset" do
    with_env(TRUSTED_PROXIES: nil) do
      assert_equal [], Relay.trusted_proxies
    end
  end

  test "trusted_proxies is empty when TRUSTED_PROXIES is blank" do
    with_env(TRUSTED_PROXIES: "  ") do
      assert_equal [], Relay.trusted_proxies
    end
  end

  test "trusted_proxies parses TRUSTED_PROXIES as a comma-separated list of CIDRs" do
    with_env(TRUSTED_PROXIES: "10.1.2.0/24, 203.0.113.0/24") do
      assert_equal [ IPAddr.new("10.1.2.0/24"), IPAddr.new("203.0.113.0/24") ], Relay.trusted_proxies
    end
  end

  test "require_tls_mx_suffixes is empty when REQUIRE_TLS_MX_SUFFIXES is unset" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: nil) do
      assert_empty Relay.require_tls_mx_suffixes
    end
  end

  test "require_tls_mx_suffixes is empty when REQUIRE_TLS_MX_SUFFIXES is blank" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: "  ") do
      assert_empty Relay.require_tls_mx_suffixes
    end
  end

  test "require_tls_mx_suffixes parses REQUIRE_TLS_MX_SUFFIXES as a comma-separated list" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com, .protonmail.ch") do
      assert_equal [ ".google.com", ".protonmail.ch" ], Relay.require_tls_mx_suffixes
    end
  end

  # Without the leading dot, the suffix would also match notgoogle.com.
  test "require_tls_mx_suffixes adds a missing leading dot and downcases" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: "Google.com,.OUTLOOK.com") do
      assert_equal [ ".google.com", ".outlook.com" ], Relay.require_tls_mx_suffixes
    end
  end

  test "sending_ips parses a name=address=helo list" do
    with_env(SENDING_IPS: "primary=203.0.113.10=mx1.example,marketing=203.0.113.11=mx2.example") do
      assert_equal [
        Relay::SendingIp.new(name: "primary", address: "203.0.113.10", helo: "mx1.example"),
        Relay::SendingIp.new(name: "marketing", address: "203.0.113.11", helo: "mx2.example")
      ], Relay.sending_ips
    end
  end

  test "sending_ips is empty when SENDING_IPS is unset" do
    with_env(SENDING_IPS: nil) do
      assert_empty Relay.sending_ips
    end
  end

  test "sending_ips raises on a malformed entry" do
    with_env(SENDING_IPS: "primary=203.0.113.10") do
      assert_raises(ArgumentError) { Relay.sending_ips }
    end
  end

  test "own_addresses are the sending IPs when SENDING_IPS is set" do
    Relay::DnsCheck.instance.addresses.create!(address: "203.0.113.99", expected_ptr_hostname: "mx.example")

    with_env(SENDING_IPS: "primary=203.0.113.10=mx1.example") do
      assert_equal [ "203.0.113.10" ], Relay.own_addresses
    end
  end

  test "own_addresses fall back to the addresses the DNS check stored for the relay hostname" do
    Relay::DnsCheck.instance.addresses.create!(address: "203.0.113.10", expected_ptr_hostname: "mx.example")

    with_env(SENDING_IPS: nil) do
      assert_equal [ "203.0.113.10" ], Relay.own_addresses
    end
  end

  test "default_sending_ip is the first entry" do
    with_env(SENDING_IPS: "primary=203.0.113.10=mx1.example,marketing=203.0.113.11=mx2.example") do
      assert_equal "203.0.113.10", Relay.default_sending_ip.address
    end
  end

  test "default_sending_ip is nil when SENDING_IPS is unset" do
    with_env(SENDING_IPS: nil) do
      assert_nil Relay.default_sending_ip
    end
  end
end
