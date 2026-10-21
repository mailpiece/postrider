require "test_helper"
require "mailresolver/testing"

class DnsResolverTest < ActiveSupport::TestCase
  FakeResolver = MailResolver::Testing::FakeResolver
  LocalNameserver = MailResolver::Testing::LocalNameserver

  test "a server failure raises TransientError rather than reading as no records" do
    resolving("mx.example" => { txt: :servfail })

    assert_raises(DnsResolver::TransientError) { DnsResolver.txt("mx.example") }
  end

  test "a timeout raises TransientError rather than reading as no records" do
    resolving("mx.example" => { txt: :timeout })

    assert_raises(DnsResolver::TransientError) { DnsResolver.txt("mx.example") }
  end

  test "a name that does not exist is an absence" do
    resolving({})

    assert_empty DnsResolver.txt("mx.example")
  end

  test "a name that exists with no records of the type asked for is an absence" do
    resolving("mx.example" => {})

    assert_empty DnsResolver.txt("mx.example")
  end

  test "a failure carries out of mail_exchangers rather than falling back to the apex" do
    resolving("example.com" => { mx: :servfail })

    assert_raises(DnsResolver::TransientError) { DnsResolver.mail_exchangers("example.com") }
  end

  test "a failure says what happened, not which library said it" do
    resolving("example.com" => { txt: :servfail })

    error = assert_raises(DnsResolver::TransientError) { DnsResolver.txt("example.com") }

    assert_equal "server failure resolving TXT example.com", error.message
    refute_includes error.message, "MailResolver"
  end

  # Real nameserver integration; doubles above only cover DnsResolver's wrapping.
  test "a SERVFAIL from a real nameserver raises TransientError" do
    LocalNameserver.answering(:servfail) do |resolver|
      DnsResolver.stubs(:resolver).returns(resolver)

      assert_raises(DnsResolver::TransientError) { DnsResolver.txt("example.com") }
    end
  end

  test "an NXDOMAIN from a real nameserver is an absence" do
    LocalNameserver.answering(:nxdomain) do |resolver|
      DnsResolver.stubs(:resolver).returns(resolver)

      assert_empty DnsResolver.txt("example.com")
    end
  end

  # Normalisation only — preference ordering is mailresolver's job.
  test "mx normalises each exchange" do
    resolving("example.com" => { mx: [ "Backup.Example.COM.", "Relay.example.com." ] })

    assert_equal %w[ backup.example.com relay.example.com ], DnsResolver.mx("example.com")
  end

  test "txt passes the records through" do
    resolving("example.com" => { txt: [ "v=DKIM1; k=rsa; p=MIIBIjAN" ] })

    assert_equal [ "v=DKIM1; k=rsa; p=MIIBIjAN" ], DnsResolver.txt("example.com")
  end

  test "addresses covers both A and AAAA" do
    resolving("mx.example" => { a: [ "203.0.113.10" ], aaaa: [ "2001:db8::10" ] })

    assert_equal %w[ 203.0.113.10 2001:db8::10 ], DnsResolver.addresses("mx.example")
  end

  test "cname returns the target rather than the name asked about" do
    resolving("mailer.example.com" => { cname: [ "Relay.Example.COM." ] })

    assert_equal %w[ relay.example.com ], DnsResolver.cname("mailer.example.com")
  end

  test "ns normalises each nameserver" do
    LocalNameserver.answering(:noerror, records: [ Resolv::DNS::Resource::IN::NS.new(Resolv::DNS::Name.create("MX.Example.")) ]) do |resolver|
      DnsResolver.stubs(:resolver).returns(resolver)

      assert_equal %w[ mx.example ], DnsResolver.ns("_acme-challenge.mx.example")
    end
  end

  test "ns reads an NXDOMAIN as an absence and a SERVFAIL as a TransientError" do
    LocalNameserver.answering(:nxdomain) do |resolver|
      DnsResolver.stubs(:resolver).returns(resolver)
      assert_empty DnsResolver.ns("_acme-challenge.mx.example")
    end

    LocalNameserver.answering(:servfail) do |resolver|
      DnsResolver.stubs(:resolver).returns(resolver)
      assert_raises(DnsResolver::TransientError) { DnsResolver.ns("_acme-challenge.mx.example") }
    end
  end

  test "name reverses the address and normalises the PTR target" do
    resolving("203.0.113.10" => { ptr: [ "MX.Example." ] })

    assert_equal "mx.example", DnsResolver.name("203.0.113.10")
  end

  test "a nonsense address resolves to nothing rather than raising" do
    assert_nil DnsResolver.name("not-an-address")
  end

  test "mail_exchangers falls back to the domain itself when it publishes no MX" do
    resolving("example.com" => {})

    assert_equal %w[ example.com ], DnsResolver.mail_exchangers("Example.com")
  end

  test "normalize strips the root label and downcases" do
    assert_equal "mx.example.com", DnsResolver.normalize("MX.Example.COM.")
  end

  test "the resolver is a MailResolver::Resolver, built once" do
    resolver = DnsResolver.send(:resolver)

    assert_instance_of MailResolver::Resolver, resolver
    assert_same resolver, DnsResolver.send(:resolver)
  end

  private
    def resolving(zone)
      DnsResolver.stubs(:resolver).returns(FakeResolver.new(zone))
    end
end
