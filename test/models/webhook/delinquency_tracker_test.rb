require "test_helper"

class Webhook::DelinquencyTrackerTest < ActiveSupport::TestCase
  setup do
    @webhook = webhooks(:active)
    @tracker = webhook_delinquency_trackers(:active)
  end

  test "a successful delivery resets the failure count" do
    @tracker.update!(consecutive_failures_count: 5, first_failure_at: 1.hour.ago)

    @tracker.record_delivery_of(delivery(state: :completed, response: { code: 200 }))

    @tracker.reload
    assert_equal 0, @tracker.consecutive_failures_count
    assert_nil @tracker.first_failure_at
  end

  test "the first failure stamps first_failure_at and later failures preserve it" do
    assert_difference -> { @tracker.reload.consecutive_failures_count }, 1 do
      @tracker.record_delivery_of(delivery(state: :completed, response: { code: 500 }))
    end
    first_failure_at = @tracker.reload.first_failure_at
    assert_not_nil first_failure_at

    assert_difference -> { @tracker.reload.consecutive_failures_count }, 1 do
      @tracker.record_delivery_of(delivery(state: :completed, response: { code: 500 }))
    end
    assert_equal first_failure_at, @tracker.reload.first_failure_at
  end

  test "enough failures sustained for long enough deactivates the webhook" do
    @tracker.update!(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)

    assert_changes -> { @webhook.reload.active? }, from: true, to: false do
      @tracker.record_delivery_of(delivery(state: :completed, response: { code: 500 }))
    end

    assert_equal "webhook_deactivated", @webhook.events.last.action
  end

  test "a failed test does not count" do
    @tracker.update!(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)

    assert_no_difference -> { @tracker.reload.consecutive_failures_count } do
      @tracker.record_delivery_of(test_delivery(response: { code: 500 }))
    end

    assert @webhook.reload.active?
  end

  test "a passing test resets the failure count" do
    @tracker.update!(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)

    @tracker.record_delivery_of(test_delivery(response: { code: 200 }))

    @tracker.reload
    assert_equal 0, @tracker.consecutive_failures_count
    assert_nil @tracker.first_failure_at
  end

  private
    def delivery(state:, response:)
      @webhook.deliveries.create!(event: deliveries(:delivered).track_event("delivered"), state: state, response: response)
    end

    def test_delivery(response:)
      @webhook.deliveries.create!(event: @webhook.track_event("tested", sent_by: "Leo"), state: :completed, response: response)
    end
end
