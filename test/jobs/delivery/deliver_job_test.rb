require "test_helper"

class Delivery::DeliverJobTest < ActiveJob::TestCase
  setup do
    @delivery = deliveries(:queued)
  end

  test "exhausting retries tracks a delivery_failed event and reports a failed delivery" do
    Delivery.any_instance.stubs(:deliver).raises(StandardError, "persistent failure")

    job = Delivery::DeliverJob.new(@delivery)

    assert_difference [ -> { Event.count },
      -> { Event.where(action: "delivery_failed", eventable: @delivery).count } ], 1 do
      (Delivery::RETRY_SCHEDULE.size + 1).times { job.perform_now }
    end

    event = @delivery.events.last
    assert_equal "delivery_failed", event.action
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
    assert @delivery.reload.exhausted?
    assert_empty Event.where(action: "delivery_bounced", eventable: @delivery)
  end

  test "a delivery deleted mid-flight discards its job instead of raising" do
    Delivery::DeliverJob.perform_later(@delivery)
    @delivery.destroy!

    assert_nothing_raised do
      perform_enqueued_jobs only: Delivery::DeliverJob
    end
  end
end
