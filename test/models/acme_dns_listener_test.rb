require "test_helper"
require "dnsruby"

class AcmeDnsListenerTest < ActiveSupport::TestCase
  include SmtpTestHelper

  self.use_transactional_tests = false

  CHALLENGE = "_acme-challenge.smtp-test.local"

  setup do
    stub_env RELAY_HOSTNAME: "smtp-test.local"
    @port = free_port
    @listener = start_listener(AcmeDnsListener, "ACME_DNS_PORT", @port)
  end

  teardown do
    stop_listener(@listener)
    Relay::Certificate.delete_all
  end

  test "answers TXT with the open challenge record, authoritatively and uncached" do
    Relay::Certificate.instance.update!(acme_challenge_records: { CHALLENGE => "token-value_123" })

    response = query(CHALLENGE, "TXT")

    assert_equal "NOERROR", response.rcode.to_s
    assert response.header.aa
    assert_not response.header.ra
    assert_equal [ [ "token-value_123" ] ], response.answer.map(&:strings)
    assert_equal [ 0 ], response.answer.map(&:ttl)
  end

  test "answers TXT case-insensitively" do
    Relay::Certificate.instance.update!(acme_challenge_records: { CHALLENGE => "token-value_123" })

    assert_equal [ "token-value_123" ], query("_ACME-Challenge.SMTP-Test.Local", "TXT").answer.first.strings
  end

  test "answers NODATA with our SOA when no challenge is open" do
    response = query(CHALLENGE, "TXT")

    assert_equal "NOERROR", response.rcode.to_s
    assert_empty response.answer
    assert_equal [ "SOA" ], response.authority.map { |rr| rr.type.to_s }
  end

  test "answers NS and SOA for the challenge name" do
    ns = query(CHALLENGE, "NS")
    soa = query(CHALLENGE, "SOA")

    assert_equal [ "smtp-test.local" ], ns.answer.map { |rr| rr.domainname.to_s }
    assert_equal [ "smtp-test.local" ], soa.answer.map { |rr| rr.mname.to_s }
    assert_equal [ "hostmaster.smtp-test.local" ], soa.answer.map { |rr| rr.rname.to_s }
  end

  test "answers NODATA for any other type at the challenge name" do
    response = query(CHALLENGE, "A")

    assert_equal "NOERROR", response.rcode.to_s
    assert_empty response.answer
    assert_equal [ "SOA" ], response.authority.map { |rr| rr.type.to_s }
  end

  test "refuses every other name" do
    [ "smtp-test.local", "example.com", "_acme-challenge.other.local", "sub._acme-challenge.smtp-test.local" ].each do |name|
      response = query(name, "TXT")

      assert_equal "REFUSED", response.rcode.to_s, name
      assert_empty response.answer
      assert_empty response.authority
    end
  end

  test "answers over TCP" do
    Relay::Certificate.instance.update!(acme_challenge_records: { CHALLENGE => "token-value_123" })

    assert_equal [ "token-value_123" ], query(CHALLENGE, "TXT", protocol: :tcp).answer.first.strings
  end

  test "survives garbage over UDP and TCP, a response and an empty question" do
    UDPSocket.new.tap { |socket| socket.send("garbage", 0, "127.0.0.1", @port) }.close
    UDPSocket.new.tap { |socket| socket.send(Dnsruby::Message.new(CHALLENGE, "TXT").tap { |m| m.header.qr = true }.encode, 0, "127.0.0.1", @port) }.close
    UDPSocket.new.tap { |socket| socket.send(Dnsruby::Message.new.encode, 0, "127.0.0.1", @port) }.close
    TCPSocket.new("127.0.0.1", @port).tap { |socket| socket.write("\x00\x05garb") }.close
    TCPSocket.new("127.0.0.1", @port).tap { |socket| socket.write("\xFF\xFF") }.close

    assert_not @listener.stopped?
    assert_equal "REFUSED", query("example.com", "TXT").rcode.to_s
  end

  test "drops an idle TCP client when its read times out and keeps serving" do
    Relay::Certificate.instance.update!(acme_challenge_records: { CHALLENGE => "token-value_123" })

    stub_const(AcmeDnsListener, :READ_TIMEOUT, 0.2) do
      idle = TCPSocket.new("127.0.0.1", @port)
      assert_equal [ "token-value_123" ], query(CHALLENGE, "TXT", protocol: :tcp).answer.first.strings
      sleep 0.5

      assert_not @listener.stopped?
      assert_equal [ "token-value_123" ], query(CHALLENGE, "TXT", protocol: :tcp).answer.first.strings
      assert_raises(EOFError) { idle.readpartial(1) }
    ensure
      idle&.close
    end
  end

  test "closes a TCP client past the cap at once and keeps serving the rest" do
    Relay::Certificate.instance.update!(acme_challenge_records: { CHALLENGE => "token-value_123" })

    stub_const(AcmeDnsListener, :MAX_TCP_CLIENTS, 2) do
      held = Array.new(2) { TCPSocket.new("127.0.0.1", @port) }
      refused = TCPSocket.new("127.0.0.1", @port)

      assert_raises(EOFError) { refused.readpartial(1) }
      assert_not @listener.stopped?

      held.each(&:close)
      sleep 0.1

      assert_equal [ "token-value_123" ], query(CHALLENGE, "TXT", protocol: :tcp).answer.first.strings
    ensure
      refused&.close
      held&.each(&:close)
    end
  end

  test "answers a query carrying records of its own, which are never read" do
    Relay::Certificate.instance.update!(acme_challenge_records: { CHALLENGE => "token-value_123" })

    socket = UDPSocket.new
    socket.connect("127.0.0.1", @port)
    socket.send(query_with_record_of_type(60_000), 0)
    response = Dnsruby::Message.decode(socket.recv(512))
    socket.close

    assert_equal 1, response.header.id
    assert_equal [ [ "token-value_123" ] ], response.answer.map(&:strings)
  end

  test "stops" do
    @listener.stop

    assert @listener.stopped?
    assert_raises(Errno::ECONNREFUSED) { TCPSocket.new("127.0.0.1", @port) }
  end

  private
    # A TXT query for the challenge name carrying one answer record of the given type.
    def query_with_record_of_type(type)
      name = CHALLENGE.split(".").map { |label| [ label.size ].pack("C") + label }.join + "\x00".b
      [ 1, 0x0100, 1, 1, 0, 0 ].pack("n6") + name + [ 16, 1 ].pack("n2") + name + [ type, 1, 0, 1 ].pack("n2Nn") + "\x00".b
    end

    def query(name, type, protocol: :udp)
      resolver = Dnsruby::Resolver.new(nameserver: "127.0.0.1", port: @port, use_tcp: protocol == :tcp,
        recurse: false, do_caching: false, dnssec: false, query_timeout: 5, retry_times: 1)
      resolver.query(name, type)
    rescue Dnsruby::NXDomain, Dnsruby::Refused => error
      error.response
    end
end
