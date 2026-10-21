require "test_helper"

class SubmissionRateLimiterTest < ActiveSupport::TestCase
  # Test env uses :null_store where increment is nil; need a real store for the windowed counter.
  around do |_test, block|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    with_env(SUBMISSION_RATE_LIMIT: 2) { block.call }
  ensure
    Rails.cache = previous_cache
  end

  setup do
    @account = accounts(:davids_account)
  end

  test "allows submissions up to the limit and refuses the next one" do
    Relay.submission_rate_limit.times do
      assert_not SubmissionRateLimiter.exceeded?(@account)
    end

    assert SubmissionRateLimiter.exceeded?(@account)
  end
end
