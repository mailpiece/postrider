require "test_helper"

class IdempotentRequestTest < ActiveSupport::TestCase
  setup do
    @sending_token = sending_tokens(:example)
  end

  test "fulfill releases the claim when the block raises" do
    assert_no_difference -> { IdempotentRequest.count } do
      assert_raises(RuntimeError) do
        IdempotentRequest.fulfill(@sending_token, "boom") { raise "boom" }
      end
    end
  end

  test "fulfill replays the linked message and reports in_progress before it links" do
    claim = @sending_token.idempotent_requests.create!(key: "k")

    assert_equal :in_progress, IdempotentRequest.fulfill(@sending_token, "k") { flunk "must not run" }.status

    claim.update!(message: messages(:queued))
    outcome = IdempotentRequest.fulfill(@sending_token, "k") { flunk "must not run" }
    assert_equal :replayed, outcome.status
    assert_equal messages(:queued), outcome.message
  end

  test "a key longer than 255 characters is invalid" do
    assert @sending_token.idempotent_requests.build(key: "x" * 255).valid?
    assert_not @sending_token.idempotent_requests.build(key: "x" * 256).valid?
  end

  test "purge_old releases a claim stranded unsettled by a dead process, but keeps a settled one" do
    stranded = @sending_token.idempotent_requests.create!(key: "stranded")
    stranded.update_column(:created_at, (IdempotentRequest::ABANDONED_AFTER + 1.minute).ago)

    settled = @sending_token.idempotent_requests.create!(key: "settled", message: messages(:queued))
    settled.update_column(:created_at, (IdempotentRequest::ABANDONED_AFTER + 1.minute).ago)

    IdempotentRequest.purge_old

    assert_not IdempotentRequest.exists?(stranded.id)
    assert IdempotentRequest.exists?(settled.id)
  end

  test "purge_old leaves an unsettled claim alone while its submission could still be running" do
    in_flight = @sending_token.idempotent_requests.create!(key: "in-flight")

    IdempotentRequest.purge_old

    assert IdempotentRequest.exists?(in_flight.id)
  end

  test "purge_old deletes rows older than 24 hours and keeps newer ones" do
    old = @sending_token.idempotent_requests.create!(key: "old")
    old.update_column(:created_at, 25.hours.ago)
    recent = @sending_token.idempotent_requests.create!(key: "recent")

    IdempotentRequest.purge_old

    assert_not IdempotentRequest.exists?(old.id)
    assert IdempotentRequest.exists?(recent.id)
  end
end
