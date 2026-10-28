require "test_helper"

class Delivery::PacingTest < ActiveSupport::TestCase
  setup do
    @delivery = deliveries(:queued)
    @delivery.domain.update!(bulk: true)
  end

  test "a bulk domain's delivery is paced before it is delivered" do
    assert_enqueued_with(job: Delivery::PaceJob, args: [ @delivery ]) do
      @delivery.deliver_later
    end
  end

  test "any other domain's delivery is delivered at once" do
    @delivery.domain.update!(bulk: false)

    assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ]) do
      @delivery.deliver_later
    end
  end

  test "bulk mail to a suppressed recipient takes no slot" do
    @delivery.domain.suppressions.create!(address: @delivery.rcpt_to)

    assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ]) do
      @delivery.deliver_later
    end
    assert_empty PacingSlot.all
  end

  test "a pace that keeps failing hands the delivery over rather than leaving it queued" do
    Delivery.any_instance.stubs(:pace).raises(ActiveRecord::StatementInvalid, "database is locked")

    assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ]) do
      perform_enqueued_jobs(only: Delivery::PaceJob) { Delivery::PaceJob.perform_later(@delivery) }
    end
  end

  test "bulk mail relayed through a smarthost is not paced" do
    with_env(OUTBOUND_RELAY: "smarthost.example:2525") do
      assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ]) do
        @delivery.deliver_later
      end
    end
  end

  test "deliveries to Outlook.com go out 30 seconds apart, whatever their domain" do
    other = deliveries(:deferred)
    @delivery.stubs(:destination_hosts).returns(%w[ hotmail-com.olc.protection.outlook.com ])
    other.stubs(:destination_hosts).returns(%w[ outlook-com.olc.protection.outlook.com ])

    freeze_time do
      assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ], at: Time.current) { @delivery.pace }
      assert_enqueued_with(job: Delivery::DeliverJob, args: [ other ], at: 30.seconds.from_now) { other.pace }
    end
  end

  test "deliveries to Outlook.com go out at BULK_OUTLOOK_MESSAGES_PER_DAY" do
    @delivery.stubs(:destination_hosts).returns(%w[ hotmail-com.olc.protection.outlook.com ])

    with_env(BULK_OUTLOOK_MESSAGES_PER_DAY: 48) do
      freeze_time do
        @delivery.pace

        assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ], at: 30.minutes.from_now) { @delivery.pace }
      end
    end
  end

  test "a rate above one a second still spaces deliveries apart" do
    @delivery.stubs(:destination_hosts).returns(%w[ mx1.example.com ])

    with_env(BULK_OTHER_MESSAGES_PER_DAY: 172800) do
      freeze_time do
        @delivery.pace

        assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ], at: 0.5.seconds.from_now) { @delivery.pace }
      end
    end
  end

  test "deliveries to any other mail server go out 2 seconds apart" do
    @delivery.stubs(:destination_hosts).returns(%w[ mx1.example.com ])

    freeze_time do
      @delivery.pace

      assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ], at: 2.seconds.from_now) { @delivery.pace }
    end
  end

  test "a delivery whose mail servers can't be looked up is delivered at once, to defer as usual" do
    @delivery.stubs(:destination_hosts).raises(DnsResolver::TransientError, "server failure")

    assert_enqueued_with(job: Delivery::DeliverJob, args: [ @delivery ]) do
      @delivery.pace
    end
    assert_empty PacingSlot.all
  end

  test "a paced delivery stays queued, with no event" do
    @delivery.stubs(:destination_hosts).returns(%w[ mx1.example.com ])

    assert_no_difference -> { Event.count } do
      @delivery.pace
    end
    assert @delivery.reload.queued?
  end
end
