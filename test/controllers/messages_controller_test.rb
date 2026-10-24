require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  test "an API client can send from_name, headers, and envelope_from" do
    post messages_path, params: {
      from: "a@example.com", from_name: "Example",
      to: [ "b@example.com" ],
      subject: "hi", text: "hello",
      headers: { "X-Test" => "1" },
      envelope_from: "bounces@example.com"
    }, headers: sending_token_env, as: :json

    assert_response :created
    message = Message.last
    assert_includes message.raw, "From: Example <a@example.com>"
    assert_includes message.raw, "X-Test: 1"
    assert_equal "bounces@example.com", message.smtp_envelope_from
  end

  test "an API client can submit a message with a bearer token" do
    assert_difference -> { Message.count } => 1, -> { Delivery.count } => 1 do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :created
    assert_equal Message.last.id, response.parsed_body["id"]
    assert_equal "queued", response.parsed_body["status"]
    assert_equal "b@example.com", Message.last.deliveries.sole.rcpt_to
  end

  test "a message containing a blocked phrase is answered like any other" do
    domains(:example).update!(blocked_phrases: "free money")

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "Free money" },
        headers: sending_token_env, as: :json
    end

    assert_response :created
    assert_equal Message.last.id, response.parsed_body["id"]
    assert_equal "queued", response.parsed_body["status"]
    assert Message.last.deliveries.sole.withheld?
  end

  test "a non-array attachments value is rejected by the model, not a bare 400" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        attachments: "not-an-array"
      }, headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "are invalid" ], response.parsed_body["attachments"]
  end

  test "an attachment with a disallowed extension is rejected" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        attachments: [ { name: "malware.exe", content_type: "application/octet-stream", content: Base64.strict_encode64("x") } ]
      }, headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "malware.exe has an unsupported file type" ], response.parsed_body["attachments"]
  end

  test "tags can be sent as a single string" do
    post messages_path, params: {
      from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      tags: "welcome"
    }, headers: sending_token_env, as: :json

    assert_response :created
    assert_equal [ "welcome" ], Message.last.tags
  end

  test "a tag sent as a hash element is rejected by the model, not silently persisted" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        tags: { "a" => 1 }
      }, headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "are invalid" ], response.parsed_body["tags"]
  end

  test "empty tags, headers, metadata, and attachments are treated as absent" do
    post messages_path, params: {
      from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      tags: [], headers: {}, metadata: {}, attachments: []
    }, headers: sending_token_env, as: :json

    assert_response :created
    assert_equal [], Message.last.tags
    assert_equal({}, Message.last.metadata)
  end

  test "an empty optional scalar is accepted rather than raising a bad request" do
    post messages_path, params: {
      from: "a@example.com", to: [ "b@example.com" ], subject: "", text: "hello"
    }, headers: sending_token_env, as: :json

    assert_response :created
  end

  test "a non-hash headers value is rejected by the model, not a bare 400" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        headers: "not-an-object"
      }, headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "must be an object" ], response.parsed_body["headers"]
  end

  test "a JSON request with an invalid bearer token is rejected" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: bearer_token_env("not-a-real-token"), as: :json
    end

    assert_response :unauthorized
  end

  test "a message with no recipients is rejected" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "needs at least one recipient in to, cc, or bcc" ], response.parsed_body["base"]
  end

  test "an object-shaped to value is rejected by the model, not a bare 400" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: { address: "b@example.com" }, subject: "hi", text: "hello"
      }, headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "needs at least one recipient in to, cc, or bcc" ], response.parsed_body["base"]
  end

  test "a logged-in operator's session cookie does not authenticate JSON requests" do
    sign_in_as :nonstaff

    post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" }, as: :json

    assert_response :unauthorized
  end

  test "a personal access token does not authenticate JSON requests" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: api_token_env, as: :json
    end

    assert_response :unauthorized
  end

  test "a missing from is rejected with a clear error instead of a false not-authorized" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: { to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :bad_request
    assert_equal "from is required", response.parsed_body["error"]
  end

  test "a domain-scoped sending token is rejected for a from address outside its domain" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@other.example", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :forbidden
  end

  test "a domain-scoped sending token is accepted for a from address inside its domain" do
    assert_difference -> { Message.count } => 1 do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :created
  end

  test "a domain-scoped sending token is rejected when its domain isn't verified yet" do
    token = domains(:unverified).sending_tokens.create!(name: "Scoped")

    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@unverified.example", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: bearer_token_env(token.token), as: :json
    end

    assert_response :forbidden
  end

  test "a domain whose sending is turned off gets a 422" do
    domains(:example).update!(sending: false)

    post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
      headers: sending_token_env, as: :json

    assert_response :unprocessable_entity
  end

  test "envelope_from cannot spoof an address the token is not authorized for" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        envelope_from: "bounces@victim.example"
      }, headers: sending_token_env, as: :json
    end

    assert_response :forbidden
    assert_equal "not authorized to send as bounces@victim.example", response.parsed_body["error"]
  end

  test "return_path cannot spoof an address the token is not authorized for" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        return_path: "bounces@victim.example"
      }, headers: sending_token_env, as: :json
    end

    assert_response :forbidden
  end

  test "a cancelled account cannot submit a message" do
    Current.account.create_cancellation!(initiated_by: users(:leo))

    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :forbidden
    assert_equal "account is not active", response.parsed_body["error"]
  end

  test "a client outside the domain's allowed IPs is forbidden" do
    domains(:example).update!(allowed_ips: "203.0.113.0/24")

    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, env: { "REMOTE_ADDR" => "198.51.100.12" }, as: :json
    end

    assert_response :forbidden
  end

  test "a client inside the domain's allowed IPs can send" do
    domains(:example).update!(allowed_ips: "203.0.113.0/24")

    assert_difference -> { Message.count } => 1 do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, env: { "REMOTE_ADDR" => "203.0.113.40" }, as: :json
    end

    assert_response :created
  end

  test "a refused sending token is recorded on its domain" do
    domains(:example).update!(allowed_ips: "203.0.113.0/24")

    with_memory_cache do
      assert_difference -> { domains(:example).events.where(action: "sending_token_refused").count }, 1 do
        post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
          headers: sending_token_env, env: { "REMOTE_ADDR" => "198.51.100.12" }, as: :json
      end
    end

    assert_response :forbidden
    event = domains(:example).events.find_by!(action: "sending_token_refused")
    assert_equal domains(:example), event.eventable
    assert_equal({ "token_name" => "Example sending token", "ip" => "198.51.100.12" }, event.particulars)
  end

  test "a sending token belonging to a different account is rejected" do
    token = domains(:other_account).sending_tokens.create!(name: "Other's token", account: accounts(:other_account))

    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: bearer_token_env(token.token), as: :json
    end

    assert_response :unauthorized
  end

  test "a sending token is marked as used after a successful send" do
    assert_nil sending_tokens(:example).last_used_at

    post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
      headers: sending_token_env, as: :json

    assert_response :created
    assert sending_tokens(:example).reload.last_used_at.present?
  end

  test "an Idempotency-Key stores the key alongside the submitted message" do
    assert_difference -> { Message.count } => 1, -> { IdempotentRequest.count } => 1 do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env.merge("Idempotency-Key" => "abc-123"), as: :json
    end

    assert_response :created
    stored = IdempotentRequest.last
    assert_equal "abc-123", stored.key
    assert_equal Message.last, stored.message
    assert_equal default_sending_token, stored.sending_token
  end

  test "a replay with the same Idempotency-Key returns the same response without resubmitting" do
    post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
      headers: sending_token_env.merge("Idempotency-Key" => "abc-123"), as: :json

    assert_response :created
    first_body = response.parsed_body

    assert_no_difference [ -> { Message.count }, -> { Delivery.count }, -> { IdempotentRequest.count } ] do
      assert_no_enqueued_jobs do
        post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
          headers: sending_token_env.merge("Idempotency-Key" => "abc-123"), as: :json
      end
    end

    assert_response :created
    assert_equal first_body, response.parsed_body
  end

  test "a concurrent first use of the same key replays the already-stored message" do
    stored_message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello")
    default_sending_token.idempotent_requests.create!(key: "race", message: stored_message)

    assert_no_difference [ -> { Message.count }, -> { IdempotentRequest.count } ] do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env.merge("Idempotency-Key" => "race"), as: :json
    end

    assert_response :created
    assert_equal stored_message.id, response.parsed_body["id"]
    assert_equal "queued", response.parsed_body["status"]
  end

  test "a key claimed by an in-flight request gets a conflict, not a resubmit" do
    default_sending_token.idempotent_requests.create!(key: "inflight")

    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env.merge("Idempotency-Key" => "inflight"), as: :json
    end

    assert_response :conflict
    assert_equal "1", response.headers["Retry-After"]
  end

  test "a failed submission releases the key so the same one can be retried" do
    assert_no_difference -> { IdempotentRequest.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi" },
        headers: sending_token_env.merge("Idempotency-Key" => "retry-me"), as: :json
    end
    assert_response :unprocessable_entity

    assert_difference -> { Message.count } => 1, -> { IdempotentRequest.count } => 1 do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env.merge("Idempotency-Key" => "retry-me"), as: :json
    end
    assert_response :created
  end

  test "an Idempotency-Key over 255 characters is rejected without claiming or submitting" do
    assert_no_difference [ -> { Message.count }, -> { IdempotentRequest.count } ] do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env.merge("Idempotency-Key" => "x" * 256), as: :json
    end

    assert_response :bad_request
  end

  test "a request without an Idempotency-Key stores no key" do
    assert_no_difference -> { IdempotentRequest.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json
    end

    assert_response :created
  end

  test "submissions beyond the account's rate limit are refused" do
    with_submission_rate_limit 2 do
      2.times do
        post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
          headers: sending_token_env, as: :json
        assert_response :created
      end

      assert_no_difference -> { Message.count } do
        post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
          headers: sending_token_env, as: :json
      end

      assert_response :too_many_requests
    end
  end

  test "the rate limit budget is shared with SMTP submissions" do
    with_submission_rate_limit 2 do
      2.times { assert_not SubmissionRateLimiter.exceeded?(accounts(:davids_account)) }

      assert_no_difference -> { Message.count } do
        post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
          headers: sending_token_env, as: :json
      end

      assert_response :too_many_requests
    end
  end

  test "an invalid token beyond the per-IP limit is rate-limited" do
    Rails.cache.stubs(:increment).returns(11)

    assert_no_difference -> { Message.count } do
      post messages_path, params: { from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: bearer_token_env("not-a-real-token"), as: :json
    end

    assert_response :too_many_requests
  end

  test "an over-limit submission is refused before an unauthorized sender is reported" do
    with_submission_rate_limit 0 do
      post messages_path, params: { from: "a@victim.example", to: [ "b@example.com" ], subject: "hi", text: "hello" },
        headers: sending_token_env, as: :json

      assert_response :too_many_requests
    end
  end

  test "the response carries the message id, recipients, and a submitted timestamp" do
    post messages_path, params: {
      from: "a@example.com", to: [ "b@example.com" ], cc: [ "c@example.com" ], subject: "hi", text: "hello"
    }, headers: sending_token_env, as: :json

    assert_response :created
    message = Message.last
    assert_equal message.mail_message_id, response.parsed_body["message_id"]
    assert_includes response.parsed_body["message_id"], "@example.com"
    assert_equal %w[ b@example.com c@example.com ], response.parsed_body["recipients"].sort
    assert_equal message.created_at.iso8601, response.parsed_body["submitted_at"]
  end

  test "a non-object metadata value is rejected by the model, not a bare 400" do
    assert_no_difference -> { Message.count } do
      post messages_path, params: {
        from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
        metadata: "not-an-object"
      }, headers: sending_token_env, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "must be an object" ], response.parsed_body["metadata"]
  end

  private
    def with_memory_cache
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = previous_cache
    end

    def with_submission_rate_limit(limit)
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      with_env(SUBMISSION_RATE_LIMIT: limit) { yield }
    ensure
      Rails.cache = previous_cache
    end
end
