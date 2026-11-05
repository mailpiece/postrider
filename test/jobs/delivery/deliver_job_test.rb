require "test_helper"

class Delivery::DeliverJobTest < ActiveJob::TestCase
  setup do
    @delivery = deliveries(:queued)
  end

  test "a first failure is retried 15 minutes later, however long ago the delivery was queued" do
    Delivery.any_instance.stubs(:deliver).raises(StandardError, "persistent failure")

    freeze_time do
      @delivery.update!(created_at: 6.days.ago)

      assert_enqueued_with job: Delivery::DeliverJob, at: 15.minutes.from_now do
        Delivery::DeliverJob.perform_now(@delivery)
      end

      assert_equal Time.current, @delivery.reload.first_failed_at
    end

    assert_not @delivery.exhausted?
  end

  test "retries back off with the time since the first failure, never more than 4000 seconds apart" do
    Delivery.any_instance.stubs(:deliver).raises(StandardError, "persistent failure")

    freeze_time do
      @delivery.update!(first_failed_at: 40.minutes.ago)
      assert_enqueued_with(job: Delivery::DeliverJob, at: 40.minutes.from_now) { Delivery::DeliverJob.perform_now(@delivery) }

      @delivery.update!(first_failed_at: 4.days.ago)
      assert_enqueued_with(job: Delivery::DeliverJob, at: 4000.seconds.from_now) { Delivery::DeliverJob.perform_now(@delivery) }
    end
  end

  test "a failure five days after the first exhausts the delivery and reports a failed delivery" do
    Delivery.any_instance.stubs(:deliver).raises(StandardError, "persistent failure")
    @delivery.update!(first_failed_at: 5.days.ago)

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      assert_difference -> { Event.where(action: "delivery_failed", eventable: @delivery).count }, 1 do
        Delivery::DeliverJob.perform_now(@delivery)
      end
    end

    event = @delivery.events.last
    assert_equal "delivery_failed", event.action
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
    assert @delivery.reload.exhausted?
    assert_empty Event.where(action: "delivery_bounced", eventable: @delivery)
  end

  test "a pause holding the delivery keeps it retrying however often it held it, until five days have passed" do
    Pause.create!(provider: "example.com", recipient_domain: "example.com")
    Delivery.any_instance.stubs(:destination_hosts).returns([ "mx.example.com" ])
    @delivery.update!(first_failed_at: 4.days.ago)
    job = Delivery::DeliverJob.new(@delivery)
    job.executions = 100

    assert_enqueued_with(job: Delivery::DeliverJob) { job.perform_now }
    assert @delivery.reload.deferred?

    travel 25.hours do
      assert_no_enqueued_jobs(only: Delivery::DeliverJob) { Delivery::DeliverJob.perform_now(@delivery) }
      assert @delivery.reload.exhausted?
    end
  end

  test "next_retry_at is when the job retries" do
    SmtpDelivery.any_instance.stubs(:deliver).returns(SmtpDelivery::Result.new(:soft_fail, "451", "greylisted", "mx.example.com", "transcript"))
    Delivery.any_instance.stubs(:destination_hosts).returns([])
    MtaStsPolicy.stubs(:lookup).returns(MtaSts::Result.new(status: "none"))

    freeze_time do
      @delivery.update!(first_failed_at: 50.minutes.ago)

      assert_enqueued_with job: Delivery::DeliverJob, at: 50.minutes.from_now do
        Delivery::DeliverJob.perform_now(@delivery)
      end

      assert_equal 50.minutes.from_now, @delivery.reload.next_retry_at
    end
  end

  test "next_retry_at of a delivery held by a pause, which made no attempt, is when the job checks again" do
    Pause.create!(provider: "example.com", recipient_domain: "example.com")
    Delivery.any_instance.stubs(:destination_hosts).returns([ "mx.example.com" ])

    freeze_time do
      Delivery::DeliverJob.perform_now(@delivery)

      assert_empty @delivery.attempts
      assert_equal 15.minutes.from_now, @delivery.reload.next_retry_at
    end
  end

  test "a delivered delivery has no next retry to show" do
    @delivery.update!(status: :delivered, next_retry_at: 1.hour.from_now)

    assert_nil @delivery.next_retry_at
  end

  test "a delivery deleted mid-flight discards its job instead of raising" do
    Delivery::DeliverJob.perform_later(@delivery)
    @delivery.destroy!

    assert_nothing_raised do
      perform_enqueued_jobs only: Delivery::DeliverJob
    end
  end
end
