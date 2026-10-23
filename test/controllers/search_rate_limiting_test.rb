require "test_helper"

class SearchRateLimitingTest < ActionDispatch::IntegrationTest
  test "a token's search under the hourly limit goes through" do
    Rails.cache.stubs(:increment).returns(SearchRateLimiting::SEARCHES_PER_HOUR)

    get search_path(format: :json), params: { q: "friend" }, env: api_token_env

    assert_response :success
  end

  test "a token's search over the hourly limit gets a 429 with Retry-After" do
    Rails.cache.stubs(:increment).returns(SearchRateLimiting::SEARCHES_PER_HOUR + 1)

    get search_path(format: :json), params: { q: "friend" }, env: api_token_env

    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
    assert_equal "Too many searches. Retry after 60 seconds.", response.parsed_body["error"]
  end

  test "searches count against one hourly budget per user" do
    Rails.cache.expects(:increment).with("rate-limit:searches:#{users(:leo).cache_key}", 1, expires_in: 1.hour).twice.returns(1)

    get search_path(format: :json), params: { q: "friend" }, env: api_token_env
    assert_response :success

    get search_path(format: :json), params: { q: "example" }, env: api_token_env
    assert_response :success
  end

  test "another user keeps their own budget" do
    token = identities(:nonstaff).access_tokens.create!(description: "Other token").token
    Rails.cache.stubs(:increment).returns(1)
    Rails.cache.stubs(:increment).with("rate-limit:searches:#{users(:leo).cache_key}", 1, expires_in: 1.hour).returns(SearchRateLimiting::SEARCHES_PER_HOUR + 1)

    get search_path(format: :json), params: { q: "friend" }, env: api_token_env
    assert_response :too_many_requests

    get search_path(format: :json), params: { q: "friend" }, env: bearer_token_env(token)
    assert_response :success
  end

  test "a search without a query is not counted" do
    Rails.cache.expects(:increment).never

    get search_path(format: :json), env: api_token_env

    assert_response :success
  end

  test "searches from a signed-in session are not counted" do
    sign_in_as :leo
    Rails.cache.expects(:increment).never

    get search_path, params: { q: "friend" }

    assert_response :success
  end
end
