require "test_helper"

class MtaStsPolicyTest < ActiveSupport::TestCase
  DISCOVERY_RECORD = "v=STSv1; id=20260730a"
  POLICY_TEXT = "version: STSv1\nmode: enforce\nmx: mail.example.com\nmax_age: 604800\n"

  test "the first lookup fetches the policy and persists a row" do
    MailResolver::Resolver.any_instance.stubs(:txt).returns([ DISCOVERY_RECORD ])
    MtaSts::Fetcher.any_instance.stubs(:fetch).returns(POLICY_TEXT)

    result = MtaStsPolicy.lookup("example.com")

    assert result.found?
    assert result.enforce?

    row = MtaStsPolicy.find_by!(domain: "example.com")
    assert_equal "20260730a", row.policy_id
    assert_equal "enforce", row.mode
    assert_equal [ "mail.example.com" ], row.mx
    assert_equal 604800, row.max_age
    assert_in_delta row.fetched_at + 604800, row.expires_at, 1
  end

  test "rediscovering the same id renews the row without refetching" do
    MailResolver::Resolver.any_instance.stubs(:txt).returns([ DISCOVERY_RECORD ])
    MtaSts::Fetcher.any_instance.expects(:fetch).once.returns(POLICY_TEXT)

    MtaStsPolicy.lookup("example.com")
    original = MtaStsPolicy.find_by!(domain: "example.com")

    travel 1.day do
      result = MtaStsPolicy.lookup("example.com")

      assert result.found?
      assert_operator MtaStsPolicy.find_by!(domain: "example.com").fetched_at, :>, original.fetched_at
    end
  end

  test "a DNS server failure returns temperror while the held policy stands" do
    MailResolver::Resolver.any_instance.stubs(:txt).raises(MailResolver::ServerFailure)
    MtaSts::Fetcher.any_instance.expects(:fetch).never

    result = MtaStsPolicy.lookup("enforced.example")

    assert result.temperror?
    assert_equal "20260730a", result.policy.id
    assert MtaStsPolicy.exists?(domain: "enforced.example")
  end

  test "a vanished TXT record reports none while the held policy stands" do
    MailResolver::Resolver.any_instance.stubs(:txt).raises(MailResolver::NotFound)
    MtaSts::Fetcher.any_instance.expects(:fetch).never

    result = MtaStsPolicy.lookup("enforced.example")

    assert result.no_record?
    assert_equal :enforce, result.policy.mode
    assert MtaStsPolicy.exists?(domain: "enforced.example")
  end

  test "purge_expired purges rows long expired but keeps live ones" do
    stale = remembered_policy(domain: "stale.example", fetched_at: 9.days.ago, max_age: 86400)
    live = mta_sts_policies(:enforced)

    MtaStsPolicy.purge_expired

    assert_not MtaStsPolicy.exists?(stale.id)
    assert MtaStsPolicy.exists?(live.id)
  end

  test "one broken domain does not halt the sweep" do
    remembered_policy(domain: "a.example")
    remembered_policy(domain: "b.example")

    MailResolver::Resolver.any_instance.stubs(:txt).raises(RuntimeError)

    assert_nothing_raised do
      MtaStsPolicy.refresh_all
    end
  end

  test "to_policy rebuilds the gem's policy from the row" do
    row = mta_sts_policies(:enforced)
    policy = row.to_policy

    assert_equal :enforce, policy.mode
    assert_equal [ "mail.enforced.example" ], policy.mx
    assert_equal 604800, policy.max_age
    assert_equal "20260730a", policy.id
    assert_equal "enforced.example", policy.domain
    assert_equal row.fetched_at, policy.fetched_at
    assert policy.allows?("mail.enforced.example")
  end

  test "to_policy is nil when the stored row no longer parses" do
    row = mta_sts_policies(:enforced)
    row.update!(mode: "bogus")

    assert_nil row.to_policy
  end

  private
    def remembered_policy(domain:, fetched_at: Time.current, max_age: 604800)
      MtaStsPolicy.create!(domain: domain, policy_id: "20260730a", mode: "enforce",
        mx: [ "mail.example.com" ], max_age: max_age, fetched_at: fetched_at, expires_at: fetched_at + max_age)
    end
end
