require "test_helper"
require "mailresolver/testing"

class InboundAuthentication::DeadlineResolverTest < ActiveSupport::TestCase
  test "gives each lookup the resolver's timeouts cut to the time left, then times out without asking" do
    zone = MailResolver::Testing::FakeResolver.new("sender.example" => { txt: [ "v=spf1 -all" ] })
    given = []
    resolver = InboundAuthentication::DeadlineResolver.new(0.1) { |timeouts| given << timeouts; zone }

    assert_equal [ "v=spf1 -all" ], resolver.txt("sender.example")
    assert_operator given.sole.sum, :<=, 0.1

    sleep 0.11
    assert_raises(MailResolver::Timeout) { resolver.txt("sender.example") }
    assert_equal 1, zone.queries.size
  end

  test "keeps the resolver's own timeouts when they fit" do
    zone = MailResolver::Testing::FakeResolver.new("sender.example" => { a: [ "192.0.2.1" ] })
    given = []
    InboundAuthentication::DeadlineResolver.new(60) { |timeouts| given << timeouts; zone }.a("sender.example")

    assert_equal MailResolver::Resolver::TIMEOUTS, given.sole
  end

  test "a lookup nobody answers ends by the deadline" do
    nameserver = MailResolver::Testing::LocalNameserver.new(nil)
    resolver = InboundAuthentication::DeadlineResolver.new(0.3) { |timeouts| nameserver.resolver(timeouts:) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_raises(MailResolver::Timeout) { resolver.txt("sender.example") }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.3 + InboundAuthentication::MailAuth::GRACE
  ensure
    nameserver&.close
  end
end
