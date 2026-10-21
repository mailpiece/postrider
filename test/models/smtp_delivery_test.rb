require "test_helper"

class SmtpDeliveryTest < ActiveSupport::TestCase
  test "deliver returns a soft failure when there are no hosts to try" do
    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: []).deliver

    assert_equal :soft_fail, result.status
    assert_nil result.code
    assert_equal "No SMTP servers available", result.output
  end

  test "a permanent session rejection is a session failure carrying its code" do
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.any_instance.stubs(:start).returns(true)
    Net::SMTP.any_instance.stubs(:finish).returns(true)
    Net::SMTP.any_instance.stubs(:mailfrom)
    Net::SMTP.any_instance.stubs(:rcptto)
    Net::SMTP.any_instance.stubs(:data).raises(Net::SMTPAuthenticationError.new("530 5.7.0 Authentication required"))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.example" ]).deliver

    assert_equal :session_fail, result.status
    assert_equal "530", result.code
    assert_equal "530 5.7.0 Authentication required", result.output
  end

  test "deliver lists connection errors in the soft failure when every host fails" do
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.any_instance.stubs(:start).raises(SocketError.new("getaddrinfo failed"))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.example" ]).deliver

    assert_equal :soft_fail, result.status
    assert_equal "No SMTP servers available: mx.example: getaddrinfo failed", result.output
  end

  test "refuses a host with no public address without connecting" do
    Surfguard.stubs(:resolve_public_ips).returns([])
    Net::SMTP.any_instance.expects(:start).never

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.internal" ]).deliver

    assert_equal :soft_fail, result.status
    assert_equal "No SMTP servers available: mx.internal: no public address", result.output
  end

  test "resolves only the first five hosts" do
    hosts = (1..7).map { |n| "mx#{n}.example" }
    hosts.first(5).each { |host| Surfguard.expects(:resolve_public_ips).with(host).returns([]) }
    hosts.last(2).each { |host| Surfguard.expects(:resolve_public_ips).with(host).never }

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: hosts).deliver

    assert_equal :soft_fail, result.status
  end

  test "resolves a host only once the ones before it have failed" do
    Surfguard.expects(:resolve_public_ips).with("mx1.example").returns([ "93.184.216.34" ])
    Surfguard.expects(:resolve_public_ips).with("mx2.example").never
    Net::SMTP.stubs(:new).returns(stub_everything(start: true, data: Net::SMTP::Response.new("250", "250 2.0.0 OK")))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: %w[ mx1.example mx2.example ]).deliver

    assert_equal :sent, result.status
  end

  test "connects to the vetted public address and sends" do
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.expects(:new).with("93.184.216.34", 25).returns(stub_everything(start: true, data: Net::SMTP::Response.new("250", "250 2.0.0 OK")))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.example" ]).deliver

    assert_equal :sent, result.status
    assert_equal "250", result.code
    assert_equal "mx.example", result.mx_host
  end

  test "the operator's outbound relay is exempt from internal-address filtering" do
    with_env(OUTBOUND_RELAY: "127.0.0.1:2525") do
      Surfguard.expects(:resolve_public_ips).never
      Net::SMTP.any_instance.stubs(:start).returns(true)
      Net::SMTP.any_instance.stubs(:finish).returns(true)
      Net::SMTP.any_instance.stubs(:mailfrom)
      Net::SMTP.any_instance.stubs(:rcptto)
      Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: []).deliver

      assert_equal :sent, result.status
      assert_equal "127.0.0.1", result.mx_host
    end
  end

  test "the operator's outbound relay keeps its self-signed certificate on port 25" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".internal.example", OUTBOUND_RELAY: "mail.internal.example:25") do
      Net::SMTP.any_instance.expects(:enable_starttls).never
      Net::SMTP.any_instance.expects(:enable_starttls_auto).with(SmtpDelivery::TLS_CONTEXT)
      Net::SMTP.any_instance.stubs(:start).returns(true)
      Net::SMTP.any_instance.stubs(:finish).returns(true)
      Net::SMTP.any_instance.stubs(:mailfrom)
      Net::SMTP.any_instance.stubs(:rcptto)
      Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: []).deliver

      assert_equal :sent, result.status
    end
  end

  test "binds the socket to the default sending IP and HELOs with its name" do
    with_env(SENDING_IPS: "primary=203.0.113.10=mx1.example") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.expects(:source_address=).with("203.0.113.10")
      Net::SMTP.any_instance.expects(:start).with("mx1.example").returns(true)
      Net::SMTP.any_instance.stubs(:mailfrom)
      Net::SMTP.any_instance.stubs(:rcptto)
      Net::SMTP.any_instance.stubs(:data).returns(stub(status: "250", string: "250 OK"))
      Net::SMTP.any_instance.stubs(:finish).returns(true)

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.example" ]).deliver

      assert_equal :sent, result.status
    end
  end

  test "leaves the source unbound and uses the configured HELO with no sending IPs" do
    with_env(SENDING_IPS: nil, HELO_HOSTNAME: "relay.example") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.expects(:source_address=).with(nil)
      Net::SMTP.any_instance.expects(:start).with("relay.example").returns(true)
      Net::SMTP.any_instance.stubs(:mailfrom)
      Net::SMTP.any_instance.stubs(:rcptto)
      Net::SMTP.any_instance.stubs(:data).returns(stub(status: "250", string: "250 OK"))
      Net::SMTP.any_instance.stubs(:finish).returns(true)

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.example" ]).deliver

      assert_equal :sent, result.status
    end
  end

  test "nothing is enforced unless REQUIRE_TLS_MX_SUFFIXES is set" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: nil) do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.stubs(:start).raises(OpenSSL::SSL::SSLError.new("handshake failure"))
      Net::SMTP.any_instance.expects(:disable_starttls).once

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "aspmx.l.google.com" ]).deliver

      assert_equal :soft_fail, result.status
    end
  end

  test "a TLS failure to a configured suffix defers instead of retrying in the clear" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.stubs(:start).raises(OpenSSL::SSL::SSLError.new("certificate verify failed"))
      Net::SMTP.any_instance.expects(:disable_starttls).never

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "aspmx.l.google.com" ]).deliver

      assert_equal :soft_fail, result.status
      assert_equal "No SMTP servers available: aspmx.l.google.com: certificate verify failed", result.output
    end
  end

  test "a TLS failure to an unlisted host still retries without STARTTLS" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.stubs(:start).raises(OpenSSL::SSL::SSLError.new("handshake failure"))
      Net::SMTP.any_instance.expects(:disable_starttls).once

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.example" ]).deliver

      assert_equal :soft_fail, result.status
      assert_equal "No SMTP servers available: mx.example: handshake failure", result.output
    end
  end

  test "a configured suffix verifies the MX name against the verified context" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.expects(:tls_hostname=).with("aspmx.l.google.com")
      Net::SMTP.any_instance.expects(:enable_starttls).with(SmtpDelivery::VERIFIED_TLS_CONTEXT)
      Net::SMTP.any_instance.expects(:enable_starttls_auto).never
      Net::SMTP.any_instance.stubs(:start).returns(true)
      Net::SMTP.any_instance.stubs(:finish).returns(true)
      Net::SMTP.any_instance.stubs(:mailfrom)
      Net::SMTP.any_instance.stubs(:rcptto)
      Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "aspmx.l.google.com" ]).deliver

      assert_equal :sent, result.status
    end
  end

  # Match and SNI must use the normalized form, not the mixed-case/rooted MX as written.
  test "an uppercase or trailing-dot MX name is matched and verified in normalized form" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.expects(:tls_hostname=).with("aspmx.l.google.com")
      Net::SMTP.any_instance.stubs(:start).raises(OpenSSL::SSL::SSLError.new("certificate verify failed"))
      Net::SMTP.any_instance.expects(:disable_starttls).never

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "ASPMX.L.GOOGLE.COM." ]).deliver

      assert_equal :soft_fail, result.status
      assert_equal "No SMTP servers available: aspmx.l.google.com: certificate verify failed", result.output
    end
  end

  test "a host merely ending in a configured suffix is not treated as a match" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.expects(:enable_starttls).never
      Net::SMTP.any_instance.expects(:enable_starttls_auto).with(SmtpDelivery::TLS_CONTEXT)
      Net::SMTP.any_instance.stubs(:start).returns(true)
      Net::SMTP.any_instance.stubs(:finish).returns(true)
      Net::SMTP.any_instance.stubs(:mailfrom)
      Net::SMTP.any_instance.stubs(:rcptto)
      Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "mx.notgoogle.com" ]).deliver

      assert_equal :sent, result.status
    end
  end

  test "a configured suffix that does not advertise STARTTLS defers" do
    with_env(REQUIRE_TLS_MX_SUFFIXES: ".google.com") do
      Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
      Net::SMTP.any_instance.stubs(:start).raises(Net::SMTPUnsupportedCommand.new("STARTTLS is not supported on this server"))
      Net::SMTP.any_instance.expects(:mailfrom).never

      result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: [ "aspmx.l.google.com" ]).deliver

      assert_equal :soft_fail, result.status
      assert_equal "No SMTP servers available: aspmx.l.google.com: STARTTLS is not supported on this server", result.output
    end
  end

  test "an enforced policy skips an MX it does not name without connecting" do
    Surfguard.expects(:resolve_public_ips).never
    Net::SMTP.any_instance.expects(:start).never

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com",
      hosts: [ "mx.imposter.example" ], policy: enforce_policy).deliver

    assert_equal :soft_fail, result.status
    assert_equal "No SMTP servers available: mx.imposter.example: not permitted by MTA-STS policy", result.output
  end

  test "an enforced policy verifies a named MX against the verified context" do
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.any_instance.expects(:tls_hostname=).with("mx.example")
    Net::SMTP.any_instance.expects(:enable_starttls).with(SmtpDelivery::VERIFIED_TLS_CONTEXT)
    Net::SMTP.any_instance.expects(:enable_starttls_auto).never
    Net::SMTP.any_instance.stubs(:start).returns(true)
    Net::SMTP.any_instance.stubs(:finish).returns(true)
    Net::SMTP.any_instance.stubs(:mailfrom)
    Net::SMTP.any_instance.stubs(:rcptto)
    Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com",
      hosts: [ "mx.example" ], policy: enforce_policy).deliver

    assert_equal :sent, result.status
  end

  test "a TLS failure under an enforced policy defers instead of retrying in the clear" do
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.any_instance.stubs(:start).raises(OpenSSL::SSL::SSLError.new("certificate verify failed"))
    Net::SMTP.any_instance.expects(:disable_starttls).never

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com",
      hosts: [ "mx.example" ], policy: enforce_policy).deliver

    assert_equal :soft_fail, result.status
    assert_equal "No SMTP servers available: mx.example: certificate verify failed", result.output
  end

  test "a testing-mode policy changes nothing about delivery" do
    policy = MtaSts::Policy.new(mode: :testing, mx: [ "mx.example" ], max_age: 86400)
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.any_instance.expects(:enable_starttls).never
    Net::SMTP.any_instance.expects(:enable_starttls_auto).with(SmtpDelivery::TLS_CONTEXT)
    Net::SMTP.any_instance.stubs(:start).returns(true)
    Net::SMTP.any_instance.stubs(:finish).returns(true)
    Net::SMTP.any_instance.stubs(:mailfrom)
    Net::SMTP.any_instance.stubs(:rcptto)
    Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com",
      hosts: [ "mx.unlisted.example" ], policy: policy).deliver

    assert_equal :sent, result.status
  end

  test "no policy leaves opportunistic delivery untouched" do
    Surfguard.stubs(:resolve_public_ips).returns([ "93.184.216.34" ])
    Net::SMTP.any_instance.expects(:enable_starttls).never
    Net::SMTP.any_instance.expects(:enable_starttls_auto).with(SmtpDelivery::TLS_CONTEXT)
    Net::SMTP.any_instance.stubs(:start).returns(true)
    Net::SMTP.any_instance.stubs(:finish).returns(true)
    Net::SMTP.any_instance.stubs(:mailfrom)
    Net::SMTP.any_instance.stubs(:rcptto)
    Net::SMTP.any_instance.stubs(:data).returns(Net::SMTP::Response.new("250", "250 2.0.0 OK"))

    result = SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com",
      hosts: [ "mx.example" ], policy: nil).deliver

    assert_equal :sent, result.status
  end

  test "a reply dripped past the command deadline is a soft failure" do
    stub_const(SmtpDelivery, :COMMAND_TIMEOUT, 0.3) do
      result = with_fake_mx(rcpt: ->(client) { loop { client.write("250-still here\r\n"); sleep 0.05 } }) do
        SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: []).deliver
      end

      assert_equal :soft_fail, result.status
      assert_equal "execution expired", result.output
    end
  end

  test "a final reply slower than the command deadline is still within the data deadline" do
    stub_const(SmtpDelivery, :COMMAND_TIMEOUT, 0.3) do
      result = with_fake_mx(data: ->(client) { sleep 0.5; client.write("250 2.0.0 queued\r\n") }) do
        SmtpDelivery.new(raw: "raw", mail_from: "a@example.com", rcpt_to: "b@example.com", hosts: []).deliver
      end

      assert_equal :sent, result.status
      assert_equal "250 2.0.0 queued", result.output
    end
  end

  private
    def with_fake_mx(rcpt: ->(client) { client.write("250 OK\r\n") }, data: ->(client) { client.write("250 OK\r\n") })
      server = TCPServer.new("127.0.0.1", 0)
      thread = Thread.new do
        client = server.accept
        client.write("220 fake ESMTP\r\n")
        while line = client.gets
          case line
          when /\AEHLO/i then client.write("250-fake\r\n250 8BITMIME\r\n")
          when /\AMAIL/i then client.write("250 OK\r\n")
          when /\ARCPT/i then rcpt.call(client)
          when /\ADATA/i
            client.write("354 go ahead\r\n")
            nil until client.gets == ".\r\n"
            data.call(client)
          when /\AQUIT/i then client.write("221 bye\r\n")
          end
        end
      rescue IOError, SystemCallError
      ensure
        client&.close
      end

      with_env(OUTBOUND_RELAY: "127.0.0.1:#{server.addr[1]}") { yield }
    ensure
      server.close
      thread.join
    end

    def enforce_policy
      MtaSts::Policy.new(mode: :enforce, mx: [ "mx.example" ], max_age: 86400)
    end
end
