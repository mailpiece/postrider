require "test_helper"

class DeliveryTest < ActiveSupport::TestCase
  setup do
    @delivery = deliveries(:queued)
    @message = @delivery.message
    @message.raw = file_fixture("raw.eml").read
    Delivery.any_instance.stubs(:destination_hosts).returns([])
    MtaStsPolicy.stubs(:lookup).returns(MtaSts::Result.new(status: "none"))
  end

  test "a new delivery inherits its subject and sender from the message" do
    delivery = @message.deliveries.create!(rcpt_to: "another@example.com")

    assert_equal @message.subject, delivery.subject
    assert_equal @message.mail_from, delivery.mail_from
  end

  test "activity_log merges events and attempts into one timeline, newest first" do
    attempt = @delivery.attempts.create!(code: "421", output: "greylisted", mx_host: "mx.example.com", created_at: 2.minutes.ago)
    event = @delivery.track_event("deferred", rcpt_to: @delivery.rcpt_to, smtp_code: "421", smtp_output: "greylisted")
    event.update_column(:created_at, 1.minute.ago)

    assert_equal [ event, attempt ], @delivery.activity_log
  end

  test "a soft failure defers the delivery and re-raises so the job retries" do
    stub_smtp(:soft_fail, "451", "greylisted, try later")

    assert_raises(RuntimeError) { @delivery.deliver }

    assert @delivery.reload.deferred?
    assert @delivery.next_retry_at.present?, "a deferred delivery should estimate its next retry"
  end

  # Transient DNS says nothing about whether the domain has MXes — defer with attempt + webhook.
  test "a transient DNS failure defers the delivery the same way an unreachable MX does" do
    Delivery.any_instance.stubs(:destination_hosts).raises(DnsResolver::TransientError, "server failure resolving MX example.com")

    assert_difference -> { Event.where(action: "delivery_deferred", eventable: @delivery).count }, 1 do
      assert_difference -> { @delivery.attempts.count }, 1 do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end

    assert @delivery.reload.deferred?
    assert_equal "server failure resolving MX example.com", @delivery.attempts.last.output
  end

  test "delivering hands the recipient domain's MTA-STS policy to smtp" do
    with_env(MTA_STS: "true") do
      Delivery.any_instance.stubs(:destination_hosts).returns([ "mx.unlisted.example" ])
      policy = MtaSts::Policy.new(mode: :enforce, mx: [ "mx.example.com" ], max_age: 86400)
      MtaStsPolicy.stubs(:lookup).with("example.com").returns(MtaSts::Result.new(status: "found", policy: policy))

      assert_raises(RuntimeError) { @delivery.deliver }

      assert @delivery.reload.deferred?
      assert_includes @delivery.attempts.last.output, "mx.unlisted.example: not permitted by MTA-STS policy"
    end
  end

  test "the operator's outbound relay skips the MTA-STS lookup" do
    with_env(MTA_STS: "true", OUTBOUND_RELAY: "smarthost.example:2525") do
      MtaStsPolicy.expects(:lookup).never
      stub_smtp(:sent, "250", "OK")

      @delivery.deliver

      assert @delivery.reload.delivered?
    end
  end

  test "MTA-STS stays off unless MTA_STS=true" do
    MtaStsPolicy.expects(:lookup).never
    stub_smtp(:sent, "250", "OK")

    @delivery.deliver

    assert @delivery.reload.delivered?
  end

  test "a soft failure dispatches a delivery_deferred webhook" do
    stub_smtp(:soft_fail, "451", "greylisted, try later")

    assert_difference -> { Event.where(action: "delivery_deferred", eventable: @delivery).count }, 1 do
      assert_raises(RuntimeError) { @delivery.deliver }
    end
  end

  # Signs with the delivery's domain even when From: is unparseable.
  test "a delivery signs with its own domain" do
    stub_smtp(:sent, "250", "OK")
    Delivery::DkimSigning.expects(:sign).with(@message.raw, domain: domains(:example)).returns(@message.raw)

    @delivery.deliver

    assert @delivery.reload.delivered?
  end

  test "a successful send marks the delivery delivered with no next retry" do
    stub_smtp(:sent, "250", "OK")

    @delivery.deliver

    assert @delivery.reload.delivered?
    assert_nil @delivery.next_retry_at
  end

  test "a successful send tracks a delivery_delivered event" do
    stub_smtp(:sent, "250", "OK")

    assert_difference -> { Event.count }, 1 do
      @delivery.deliver
    end

    event = @delivery.events.last
    assert_equal "delivery_delivered", event.action
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
  end

  test "deliver on a delivery in a terminal state never attempts smtp" do
    SmtpDelivery.any_instance.expects(:deliver).never

    %w[ delivered bounced suppressed withheld exhausted ].each do |status|
      @delivery.update!(status: status)

      assert_no_difference -> { @delivery.attempts.count } do
        @delivery.deliver
      end
    end
  end

  test "deliver on a deferred delivery re-sends so soft-fail retries still deliver" do
    @delivery.update!(status: :deferred)
    stub_smtp(:sent, "250", "OK")

    assert_difference -> { @delivery.attempts.count }, 1 do
      @delivery.deliver
    end

    assert @delivery.reload.delivered?
  end

  test "a send whose event fails is rolled back for the retry" do
    stub_smtp(:sent, "250", "OK")
    Event.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_no_difference -> { @delivery.attempts.count } do
      assert_raises(ActiveRecord::RecordInvalid) { @delivery.deliver }
    end

    assert @delivery.reload.queued?
  end

  test "a bounce whose event fails is rolled back for the retry" do
    stub_smtp(:hard_fail, "550", "no such user")
    Event.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_no_difference -> { Suppression.count } do
      assert_raises(ActiveRecord::RecordInvalid) { @delivery.deliver }
    end

    assert @delivery.reload.queued?
  end

  test "a hard failure marks the delivery bounced" do
    stub_smtp(:hard_fail, "550", "no such user")

    @delivery.deliver

    assert @delivery.reload.bounced?
  end

  test "a hard failure tracks a delivery_bounced event" do
    stub_smtp(:hard_fail, "550", "no such user")

    assert_difference -> { Event.count }, 1 do
      @delivery.deliver
    end

    event = @delivery.events.last
    assert_equal "delivery_bounced", event.action
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
    assert_equal "550", event.particulars["smtp_code"]
    assert_equal "invalid", event.particulars["category"]
  end

  test "a soft failure tracks a deferral, kept out of the feed so retries cannot flood it" do
    stub_smtp(:soft_fail, "451", "greylisted, try later")

    assert_difference -> { Event.count }, 1 do
      assert_raises(RuntimeError) { @delivery.deliver }
    end

    event = @delivery.events.last
    assert_equal "delivery_deferred", event.action
    assert_equal "451", event.particulars["smtp_code"]
    assert_empty @delivery.events.notable
  end

  test "a hard failure suppresses the recipient" do
    stub_smtp(:hard_fail, "550", "no such user")

    assert_difference -> { Current.account.suppressions.count }, 1 do
      @delivery.deliver
    end

    assert_equal "invalid", Current.account.suppressions.find_by(address: "recipient@example.com").reason
  end

  test "a hard failure of the relay's own mail does not suppress the recipient" do
    @message.update!(origin: :system)
    stub_smtp(:hard_fail, "550", "no such user")

    assert_no_difference -> { Current.account.suppressions.count } do
      @delivery.deliver
    end
    assert @delivery.reload.bounced?
  end

  test "a rejection aimed at us defers instead of bouncing, and never suppresses" do
    stub_smtp(:hard_fail, "550", "5.7.1 Message rejected by spam filter")

    assert_no_difference -> { Current.account.suppressions.count } do
      assert_raises(RuntimeError) { @delivery.deliver }
    end

    assert @delivery.reload.deferred?
    assert_equal "delivery_deferred", @delivery.events.last.action
  end

  test "a blocklisting that quotes our own IP pauses sending to the recipient's domain" do
    microsoft = "5.7.1 Service unavailable, Client host [203.0.113.7] blocked using Spamhaus. To request removal from this list see https://www.spamhaus.org/query/ip/203.0.113.7 (S3150)"

    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", microsoft)

      assert_difference -> { Pause.count }, 1 do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end

    pause = Pause.find_by!(provider: "example.com")
    assert_equal @delivery, pause.delivery
    assert_equal microsoft, pause.smtp_output
    assert @delivery.reload.deferred?
    assert_equal "example.com", @delivery.events.find_by!(action: "recipient_domain_paused").particulars["recipient_domain"]
  end

  test "a blocklisting from Outlook.com pauses every domain it hosts" do
    @delivery.stubs(:destination_hosts).returns(%w[ example-com.olc.protection.outlook.com ])
    SmtpDelivery.any_instance.stubs(:deliver).returns(
      SmtpDelivery::Result.new(:hard_fail, "550", "5.7.1 [203.0.113.7] is on our block list (S3150)", "example-com.olc.protection.outlook.com", "transcript"))

    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      assert_raises(RuntimeError) { @delivery.deliver }
    end

    pause = Pause.find_by!(provider: "outlook")
    assert_equal "example.com", pause.recipient_domain
    assert_equal "outlook", @delivery.events.find_by!(action: "recipient_domain_paused").particulars["provider"]
  end

  test "a blocklisting from a backup MX on Gmail pauses only the domain whose first MX is its own" do
    @delivery.stubs(:destination_hosts).returns(%w[ mx1.example.com aspmx.l.google.com ])
    SmtpDelivery.any_instance.stubs(:deliver).returns(
      SmtpDelivery::Result.new(:hard_fail, "550", "5.7.1 [203.0.113.7] is listed on Spamhaus", "aspmx.l.google.com", "transcript"))

    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      assert_raises(RuntimeError) { @delivery.deliver }
    end

    assert Pause.exists?(provider: "example.com")
    assert_not Pause.exists?(provider: "gmail")
  end

  test "Gmail's unusual rate of unsolicited mail from our IP pauses" do
    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", "5.7.1 [203.0.113.7] Our system has detected an unusual rate of unsolicited mail originating from your IP address.")

      assert_difference -> { Pause.count }, 1 do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "Gmail's verdict on one message never pauses, though it quotes our IP" do
    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", "5.7.1 [203.0.113.7] Gmail has detected that this message is likely unsolicited mail.")

      assert_no_difference -> { Pause.count } do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "Gmail's verdict on the sending domain's reputation never pauses, though it quotes our IP" do
    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", "5.7.1 [203.0.113.7] This message is likely suspicious due to the very low reputation of the sending domain.")

      assert_no_difference -> { Pause.count } do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "a rejection that quotes our IP without naming a blocklist never pauses" do
    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", "5.7.26 [203.0.113.7] Unauthenticated email from example.com is not accepted due to its DMARC policy.")

      assert_no_difference -> { Pause.count } do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "a block that does not quote our IP never pauses, whatever it says" do
    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", "5.7.1 Message rejected as spam, 198.51.100.4 is listed on Spamhaus")

      assert_no_difference -> { Pause.count } do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "without SENDING_IPS our IP is the one the last DNS check found for the relay hostname" do
    Relay::DnsCheck.instance.addresses.create!(address: "203.0.113.7", expected_ptr_hostname: "mx.example")

    with_env(SENDING_IPS: nil) do
      stub_smtp(:hard_fail, "550", "5.7.1 [203.0.113.7] is listed on Spamhaus")

      assert_difference -> { Pause.count }, 1 do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "a blocklisting that quotes our IP never pauses while relaying through a smarthost" do
    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example", OUTBOUND_RELAY: "smarthost.example:2525") do
      stub_smtp(:hard_fail, "550", "5.7.1 [203.0.113.7] is listed on Spamhaus")

      assert_no_difference -> { Pause.count } do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end
  end

  test "a domain paused by another delivery meanwhile keeps this attempt and its deferral" do
    Pause.create!(provider: "example.com", recipient_domain: "example.com", delivery: deliveries(:deferred))
    @delivery.stubs(:provider_paused?).returns(false)

    with_env(SENDING_IPS: "primary=203.0.113.7=mx.example") do
      stub_smtp(:hard_fail, "550", "5.7.1 [203.0.113.7] is listed on Spamhaus")

      assert_no_difference -> { Event.where(action: "recipient_domain_paused").count } do
        assert_raises(RuntimeError) { @delivery.deliver }
      end
    end

    assert @delivery.reload.deferred?
    assert_equal 1, @delivery.attempts.count
  end

  test "a delivery to a paused domain defers without connecting and keeps retrying" do
    Pause.create!(provider: "example.com", recipient_domain: "example.com")
    SmtpDelivery.any_instance.expects(:deliver).never

    assert_raises(RuntimeError) { @delivery.deliver }

    assert @delivery.reload.deferred?
    assert_empty @delivery.attempts
    assert_equal "recipient_domain_paused", @delivery.events.find_by!(action: "delivery_deferred").particulars["reason"]
  end

  test "a delivery to another domain on a paused provider defers without connecting" do
    Pause.create!(provider: "outlook", recipient_domain: "hotmail.com")
    @delivery.stubs(:destination_hosts).returns(%w[ example-com.olc.protection.outlook.com ])
    SmtpDelivery.any_instance.expects(:deliver).never

    assert_raises(RuntimeError) { @delivery.deliver }

    assert @delivery.reload.deferred?
    assert_empty @delivery.attempts
  end

  test "a pause on a provider does not hold a domain on another MX" do
    Pause.create!(provider: "outlook", recipient_domain: "hotmail.com")
    @delivery.stubs(:destination_hosts).returns(%w[ example-com.mail.protection.outlook.com ])
    stub_smtp(:sent, "250", "OK")

    @delivery.deliver

    assert @delivery.reload.delivered?
  end

  test "a delivery held by a pause has no next retry to show" do
    @delivery.attempts.create!(code: "451", output: "greylisted", mx_host: "mx.example.com", created_at: 3.hours.ago)
    Pause.create!(provider: "example.com", recipient_domain: "example.com")

    assert_raises(RuntimeError) { @delivery.deliver }

    assert @delivery.reload.deferred?
    assert_nil @delivery.next_retry_at
  end

  test "a paused domain does not hold mail relayed through a smarthost" do
    Pause.create!(provider: "example.com", recipient_domain: "example.com")

    with_env(OUTBOUND_RELAY: "smarthost.example:2525") do
      stub_smtp(:sent, "250", "OK")

      @delivery.deliver
    end

    assert @delivery.reload.delivered?
  end

  test "webhook_payload for a paused domain names the domain and the provider paused" do
    @delivery.track_recipient_domain_event "paused", provider: "outlook"

    assert_equal "example.com", @delivery.webhook_payload("recipient_domain_paused")[:recipient_domain]
    assert_equal "outlook", @delivery.webhook_payload("recipient_domain_paused")[:provider]
  end

  test "webhook_payload for a deferral carries its reason when it has one" do
    Pause.create!(provider: "example.com", recipient_domain: "example.com")
    assert_raises(RuntimeError) { @delivery.deliver }

    assert_equal "recipient_domain_paused", @delivery.webhook_payload("delivery_deferred")[:reason]
  end

  test "webhook_payload for a pause from before providers names the domain as the provider" do
    @delivery.track_recipient_domain_event "paused"

    assert_equal "example.com", @delivery.webhook_payload("recipient_domain_paused")[:provider]
  end

  test "webhook_payload for an ordinary deferral has no reason" do
    stub_smtp(:soft_fail, "451", "greylisted, try later")
    assert_raises(RuntimeError) { @delivery.deliver }

    assert_not @delivery.webhook_payload("delivery_deferred").key?(:reason)
  end

  test "webhook_payload for a failure carries its reason" do
    domains(:example).suppressions.create!(address: "recipient@example.com")
    @delivery.deliver

    assert_equal "suppressed", @delivery.webhook_payload("delivery_failed")[:reason]
  end

  test "a full mailbox bounces without suppressing an address that plainly exists" do
    stub_smtp(:hard_fail, "552", "5.2.2 Mailbox full")

    assert_no_difference -> { Current.account.suppressions.count } do
      @delivery.deliver
    end

    assert @delivery.reload.bounced?
    assert_equal "full", @delivery.events.last.particulars["category"]
  end

  test "a suppression stops blocking mail once it expires" do
    stub_smtp(:hard_fail, "550", "no such user")
    @delivery.deliver
    suppression = Current.account.suppressions.find_by(address: "recipient@example.com")

    assert Current.account.suppressions.active.exists?(id: suppression.id)

    suppression.update!(expires_at: 1.day.ago)

    assert_not Current.account.suppressions.active.exists?(id: suppression.id)
    assert suppression.expired?
    assert Current.account.suppressions.exists?(id: suppression.id), "an expired suppression is kept for the record"
  end

  test "a permanent session failure exhausts the delivery without suppressing the recipient" do
    stub_smtp(:session_fail, "530", "authentication required")

    assert_no_difference -> { Current.account.suppressions.count } do
      @delivery.deliver
    end

    assert @delivery.reload.exhausted?
  end

  test "a permanent session failure tracks a delivery_failed event" do
    stub_smtp(:session_fail, "530", "authentication required")

    assert_difference -> { Event.count }, 1 do
      @delivery.deliver
    end

    event = @delivery.events.last
    assert_equal "delivery_failed", event.action
    assert_equal "exhausted", event.particulars["reason"]
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
  end

  test "a permanent session failure dispatches a delivery_failed webhook without a bounce report" do
    stub_smtp(:session_fail, "530", "authentication required")

    assert_difference -> { Event.where(action: "delivery_failed", eventable: @delivery).count }, 1 do
      assert_no_difference -> { Event.where(action: "delivery_bounced").count } do
        @delivery.deliver
      end
    end
  end

  test "a delivery to a suppressed recipient never attempts smtp and is marked suppressed" do
    domains(:example).suppressions.create!(address: "recipient@example.com")
    SmtpDelivery.any_instance.expects(:deliver).never

    @delivery.deliver

    assert @delivery.reload.suppressed?
    assert_empty @delivery.attempts
  end

  test "a delivery is not suppressed by another domain's suppression" do
    domains(:private).suppressions.create!(address: "recipient@example.com")
    SmtpDelivery.any_instance.expects(:deliver).returns(SmtpDelivery::Result.new(status: :sent, code: 250, output: "OK"))

    @delivery.deliver

    assert_not @delivery.reload.suppressed?
  end

  test "a delivery to a suppressed recipient tracks a delivery_failed event" do
    domains(:example).suppressions.create!(address: "recipient@example.com")

    assert_difference -> { Event.count }, 1 do
      @delivery.deliver
    end

    event = @delivery.events.last
    assert_equal "delivery_failed", event.action
    assert_equal "suppressed", event.particulars["reason"]
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
  end

  test "in_flight scope covers queued and deferred deliveries only" do
    in_flight = Delivery.in_flight

    assert_includes in_flight, deliveries(:queued)
    assert_includes in_flight, deliveries(:deferred)
    assert_not_includes in_flight, deliveries(:delivered)
    assert_not_includes in_flight, deliveries(:bounced)
  end

  test "deliveries carry a composite index on account and status for the deferred backlog count" do
    columns = @message.class.connection.indexes(:deliveries).map(&:columns)

    assert_includes columns, %w[ account_id status ]
  end

  test "smtp_envelope_from uses an explicitly set envelope_from" do
    @message.update!(envelope_from: "custom@example.com")

    assert_equal "custom@example.com", @delivery.smtp_envelope_from
  end

  test "smtp_envelope_from preserves an intentional null return path even with a VERP domain enabled" do
    verp_enabled_domain
    @message.update!(envelope_from: "")

    assert_equal "", @delivery.smtp_envelope_from
  end

  test "smtp_envelope_from uses a VERP return path when the sending domain has one enabled" do
    verp_enabled_domain

    assert_equal Delivery::ReturnPath.new(@delivery).address, @delivery.smtp_envelope_from
    assert_match(/\Abounces\+.+@mailer\.example\.com\z/, @delivery.smtp_envelope_from)
  end

  test "smtp_envelope_from of the relay's own mail is null to an MX, and the relay's return path through an outbound relay" do
    verp_enabled_domain
    @message.update!(origin: :system, envelope_from: "")

    assert_equal "", @delivery.smtp_envelope_from

    with_env(OUTBOUND_RELAY: "smarthost.example:2525", RELAY_MAIL_DOMAIN: "relay.example") do
      assert_equal Delivery::ReturnPath.verp.address_for(@delivery.id, domain: "relay.example"), @delivery.smtp_envelope_from
    end
  end

  test "smtp_envelope_from falls back to the message From address without a VERP domain" do
    assert_equal @message.smtp_envelope_from, @delivery.smtp_envelope_from
    assert_equal "sender@example.com", @delivery.smtp_envelope_from
  end

  test "record_async_bounce appends a bounced event carrying the raw DSN without changing delivered status" do
    assert_difference -> { deliveries(:delivered).events.count }, 1 do
      deliveries(:delivered).record_async_bounce(dsn_raw: "raw-inbound-dsn")
    end

    assert deliveries(:delivered).reload.delivered?, "an async bounce must not rewrite the recorded delivered handoff"
    event = deliveries(:delivered).events.last
    assert_equal "delivery_bounced", event.action
    assert_equal "recipient@example.com", event.particulars["rcpt_to"]
    assert_equal "dsn", event.particulars["source"]
    assert_equal "raw-inbound-dsn", event.particulars["dsn"]
  end

  test "record_async_bounce stores at most 64KB of the DSN" do
    deliveries(:delivered).record_async_bounce(dsn_raw: "x" * (Delivery::Bouncing::STORED_DSN_LIMIT + 1))

    assert_equal Delivery::Bouncing::STORED_DSN_LIMIT, deliveries(:delivered).events.last.particulars["dsn"].bytesize
  end

  test "record_async_bounce suppresses a recipient the report says is invalid" do
    assert_difference -> { Current.account.suppressions.count }, 1 do
      deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn)
    end

    suppression = Current.account.suppressions.find_by(address: "recipient@example.com")
    assert_equal "invalid", suppression.reason
    assert_equal Suppression::LIFETIME.from_now.to_date, suppression.expires_at.to_date
    assert_equal "invalid", deliveries(:delivered).events.last.particulars["category"]
  end

  test "record_async_bounce leaves the recipient alone when the report is only a delay notice" do
    assert_no_difference -> { Current.account.suppressions.count } do
      deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn(action: "delayed", status: "4.4.7"))
    end
  end

  test "record_async_bounce leaves a full mailbox alone, however permanent the report reads" do
    assert_no_difference -> { Current.account.suppressions.count } do
      deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn(status: "5.2.2"))
    end

    assert_equal "full", deliveries(:delivered).events.last.particulars["category"]
  end

  test "record_async_bounce spares an address whose report quotes our own address" do
    with_env(SENDING_IPS: "primary=203.0.113.9=relay.example.com") do
      assert_no_difference -> { Current.account.suppressions.count } do
        deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn(diagnostic: "smtp; 550 5.1.1 rejected because 203.0.113.9 is on a blocklist"))
      end
    end
  end

  test "record_async_bounce tells the tenant about a report it cannot read, but acts on nothing" do
    assert_difference -> { Event.where(action: "delivery_bounced", eventable: deliveries(:delivered)).count }, 1 do
      assert_no_difference -> { Current.account.suppressions.count } do
        deliveries(:delivered).record_async_bounce(dsn_raw: "a human-readable bounce with no report part")
      end
    end

    assert deliveries(:delivered).events.last.particulars.key?("category")
    assert_nil deliveries(:delivered).events.last.particulars["category"]
    payload = deliveries(:delivered).webhook_payload("delivery_bounced")
    assert payload.key?(:category)
    assert_nil payload[:category]
  end

  test "record_async_bounce dispatches a delivery_bounced webhook" do
    assert_difference -> { Event.where(action: "delivery_bounced", eventable: deliveries(:delivered)).count }, 1 do
      deliveries(:delivered).record_async_bounce(dsn_raw: "raw-inbound-dsn")
    end
  end

  test "record_async_bounce ignores a re-sent DSN so it never double-suppresses or double-notifies" do
    deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn)

    assert_no_difference [ -> { deliveries(:delivered).events.reload.size }, -> { Current.account.suppressions.count }, -> { Event.count } ] do
      deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn)
    end
  end

  test "webhook_payload for delivery_bounced prefers the stored inbound DSN over the synthesized report" do
    deliveries(:delivered).record_async_bounce(dsn_raw: failing_dsn)

    payload = deliveries(:delivered).webhook_payload("delivery_bounced")
    assert_equal failing_dsn, payload[:raw]
    assert_equal "invalid", payload[:category]
  end

  test "exhaust reports a failed delivery, never a bounce the remote never sent" do
    @delivery.attempts.create!(code: "421", output: "service unavailable", mx_host: "mx.example.com")

    assert_difference -> { Event.where(action: "delivery_failed", eventable: @delivery).count }, 1 do
      assert_no_difference -> { Event.where(action: "delivery_bounced", eventable: @delivery).count } do
        @delivery.exhaust
      end
    end

    assert @delivery.exhausted?
    assert_equal "delivery_failed", @delivery.events.last.action
  end

  test "an exhausted delivery that later receives a real DSN reports one bounce, carrying the real DSN" do
    @delivery.attempts.create!(code: "421", output: "service unavailable", mx_host: "mx.example.com")
    @delivery.exhaust

    assert_difference [ -> { Event.where(action: "delivery_bounced", eventable: @delivery).count },
      -> { Current.account.suppressions.count } ], 1 do
      @delivery.record_async_bounce(dsn_raw: failing_dsn)
    end

    assert_equal failing_dsn, @delivery.webhook_payload("delivery_bounced")[:raw]
  end

  test "webhook_payload for delivery_bounced falls back to the synthesized DSN on the synchronous path" do
    stub_smtp(:hard_fail, "550", "no such user")
    @delivery.deliver

    payload = @delivery.webhook_payload("delivery_bounced")
    assert_includes payload[:raw], "Final-Recipient"
    assert_includes payload[:raw], "recipient@example.com"
    assert_equal "invalid", payload[:category]
  end

  test "ordinary mail goes out signed with its own domain's DKIM key" do
    Delivery::DkimSigning.expects(:sign).with(@message.raw, domain: @message.domain).returns(@message.raw)
    stub_smtp(:sent, "250", "OK")

    @delivery.deliver

    assert @delivery.reload.delivered?
  end

  test "a forward is never signed with the tenant's key — it carries the relay's ARC seal instead" do
    @message.update!(origin: :forwarded)
    Delivery::DkimSigning.expects(:sign).never
    stub_smtp(:sent, "250", "OK")

    @delivery.deliver

    assert @delivery.reload.delivered?
  end

  private
    def verp_enabled_domain
      domains(:example).update!(dmarc_status: :ok, return_path_status: :ok)
    end

    def failing_dsn(action: "failed", status: "5.1.1", diagnostic: nil)
      per_recipient = "Final-Recipient: rfc822; recipient@example.com\r\nAction: #{action}\r\nStatus: #{status}\r\n"
      per_recipient += "Diagnostic-Code: #{diagnostic}\r\n" if diagnostic

      "From: MAILER-DAEMON@mx.example.com\r\nSubject: Undelivered Mail Returned to Sender\r\n" \
        "Content-Type: multipart/report; report-type=delivery-status; boundary=\"BB\"\r\n\r\n" \
        "--BB\r\nContent-Type: text/plain\r\n\r\nDelivery to the recipient failed.\r\n\r\n" \
        "--BB\r\nContent-Type: message/delivery-status\r\n\r\nReporting-MTA: dns; mx.example.com\r\n\r\n" \
        "#{per_recipient}\r\n--BB--\r\n"
    end

    def stub_smtp(status, code, output)
      SmtpDelivery.any_instance.stubs(:deliver).returns(
        SmtpDelivery::Result.new(status, code, output, "mx.example.com", "transcript")
      )
    end
end
