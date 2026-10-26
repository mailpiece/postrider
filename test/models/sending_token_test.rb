require "test_helper"

class SendingTokenTest < ActiveSupport::TestCase
  test "assigns a digest on create and never persists the raw token" do
    token = domains(:example).sending_tokens.create!(name: "API")

    assert token.token.present?
    assert_equal SendingToken.digest(token.token), token.token_digest
    assert_equal token, SendingToken.authenticate(token.token)
  end

  test "a token may send only as its own pinned domain" do
    assert sending_tokens(:example).authorizes_sending_as?("news@example.com")
    assert_not sending_tokens(:example).authorizes_sending_as?("news@private.example")
  end

  test "a token may not send as its pinned domain while unverified" do
    token = domains(:unverified).sending_tokens.create!(name: "Scoped")

    assert_not token.authorizes_sending_as?("news@unverified.example")
  end

  test "a token takes its account from its domain" do
    token = domains(:other_account).sending_tokens.create!(name: "Theirs")

    assert_equal accounts(:other_account), token.account
  end

  test "a new token is prefixed" do
    token = domains(:example).sending_tokens.create!(name: "API")

    assert_match(/\Apostrider_[1-9A-HJ-NP-Za-km-z]{44}\z/, token.token)
  end

  test "a token from before the prefix still authenticates" do
    assert_equal sending_tokens(:example), SendingToken.authenticate(DomainTestHelper::SENDING_TOKEN)
  end

  test "creating and revoking a token is recorded on its domain" do
    token = domains(:example).sending_tokens.create!(name: "Production")
    token.destroy!

    assert_equal "Production", domains(:example).events.find_by!(eventable: domains(:example), action: "sending_token_created").particulars["token_name"]
    assert_equal "Production", domains(:example).events.find_by!(eventable: domains(:example), action: "sending_token_revoked").particulars["token_name"]
  end

  test "destroying a domain records no revocation for its tokens" do
    domain = domains(:unverified)
    domain.sending_tokens.create!(name: "Scoped")

    assert_difference -> { Domain.count }, -1 do
      domain.destroy!
    end
    assert_not Event.exists?(action: "sending_token_revoked")
  end

  test "a refusal is recorded once an hour for each address" do
    with_memory_cache do
      assert_difference -> { refusals.count }, 2 do
        sending_tokens(:example).refuse("198.51.100.12")
        sending_tokens(:example).refuse("198.51.100.12")
        sending_tokens(:example).refuse("198.51.100.13")
      end
    end
  end

  test "an IPv4-mapped address counts as its IPv4 form" do
    with_memory_cache do
      assert_difference -> { refusals.count }, 1 do
        sending_tokens(:example).refuse("::ffff:198.51.100.12")
        sending_tokens(:example).refuse("198.51.100.12")
      end
    end

    assert_equal "198.51.100.12", refusals.sole.particulars["ip"]
  end

  test "addresses in one IPv6 /64 count as one" do
    with_memory_cache do
      assert_difference -> { refusals.count }, 1 do
        sending_tokens(:example).refuse("2001:db8::1")
        sending_tokens(:example).refuse("2001:db8::ffff:2")
      end
    end
  end

  test "refusals stop being recorded past the hourly ceiling for a token" do
    with_memory_cache do
      assert_difference -> { refusals.count }, SendingToken::MAX_REFUSALS_RECORDED_PER_HOUR do
        (SendingToken::MAX_REFUSALS_RECORDED_PER_HOUR + 1).times { |i| sending_tokens(:example).refuse("198.51.100.#{i}") }
      end
    end
  end

  test "an unparsable address records nothing" do
    with_memory_cache do
      assert_no_difference -> { refusals.count } do
        sending_tokens(:example).refuse("not an ip")
      end
    end
  end

  private
    def refusals
      domains(:example).events.where(action: "sending_token_refused")
    end

    def with_memory_cache
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = previous_cache
    end
end
