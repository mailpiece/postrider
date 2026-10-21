require "test_helper"

class Webhook::DeliveryTest < ActiveSupport::TestCase
  PUBLIC_TEST_IP = "93.184.216.34"

  setup do
    stub_dns_resolution(PUBLIC_TEST_IP)
    @webhook = webhooks(:active)
    @event = deliveries(:delivered).track_event("delivered")
  end

  test "a new delivery starts pending" do
    assert_equal "pending", build_delivery.state
  end

  test "succeeded? requires a completed 2xx response without an error" do
    delivery = @webhook.deliveries.build(event: @event, response: { code: 200 }, state: :completed)
    assert delivery.succeeded?

    delivery.response[:code] = 422
    assert_not delivery.succeeded?

    delivery.response[:code] = 200
    delivery.state = :pending
    assert_not delivery.succeeded?

    delivery.state = :in_progress
    assert_not delivery.succeeded?

    delivery.state = :errored
    assert_not delivery.succeeded?

    delivery.state = :completed
    delivery.response[:error] = :destination_unreachable
    assert_not delivery.succeeded?
  end

  test "failed? is a completed or errored delivery that did not succeed" do
    delivery = @webhook.deliveries.build(event: @event, response: { code: 200 }, state: :completed)
    assert_not delivery.failed?

    delivery.response[:code] = 500
    assert delivery.failed?

    delivery.state = :pending
    assert_not delivery.failed?

    delivery.state = :errored
    assert delivery.failed?
  end

  test "sanitized_request strips the signature header" do
    delivery = build_delivery
    delivery.update!(request: { headers: {
      "User-Agent" => "postrider/1.0.0 Webhook",
      "X-Webhook-Signature" => "secret",
      "X-Webhook-Timestamp" => "2026-06-30T00:00:00Z"
    } })

    assert_not delivery.sanitized_request[:headers].key?("X-Webhook-Signature")
  end

  test "sanitized_request strips the Authorization header" do
    delivery = build_delivery
    delivery.update!(request: { headers: {
      "User-Agent" => "postrider/1.0.0 Webhook",
      "Authorization" => "Basic secret"
    } })

    assert_not delivery.sanitized_request[:headers].key?("Authorization")
  end

  test "sanitized_request returns nil when request is blank" do
    delivery = build_delivery
    delivery.update_columns(request: nil)

    assert_nil delivery.sanitized_request
  end

  test "response_summary returns code and error" do
    delivery = build_delivery
    delivery.update!(response: { code: 200, error: nil })

    assert_equal 200, delivery.response_summary[:code]
    assert_nil delivery.response_summary[:error]
  end

  test "response_summary returns nil when response is blank" do
    delivery = build_delivery
    delivery.update_columns(response: nil)

    assert_nil delivery.response_summary
  end

  test "deliver_later enqueues the delivery job" do
    delivery = build_delivery
    assert_enqueued_with job: Webhook::DeliveryJob, args: [ delivery ] do
      delivery.deliver_later
    end
  end

  test "deliver posts a signed JSON body and completes on 2xx" do
    delivery = build_delivery

    request = stub_request(:post, @webhook.url)
      .with(headers: { "Content-Type" => "application/json" }) { |req|
        req.headers["X-Webhook-Signature"].present? && JSON.parse(req.body)["event"] == "delivery_delivered"
      }
      .to_return(status: 200)

    delivery.deliver

    assert_requested request
    assert_equal "completed", delivery.state
    assert_equal 200, delivery.response[:code]
    assert delivery.succeeded?
  end

  test "deliver posts without TLS to an http endpoint" do
    @webhook.update!(url: "http://example.com/webhook")
    delivery = build_delivery
    request = stub_request(:post, "http://example.com/webhook").to_return(status: 200)

    delivery.deliver

    assert_requested request
    assert delivery.succeeded?
  end

  test "deliver posts the raw MIME body with Basic Auth to an Action Mailbox relay webhook" do
    email = inbound_emails(:received)
    email.raw = file_fixture("raw.eml").read
    delivery = relay_webhook.deliveries.create!(event: email.track_event("received"))

    expected_auth = "Basic #{Base64.strict_encode64("actionmailbox:#{relay_webhook.signing_secret}")}"

    request = stub_request(:post, relay_webhook.url)
      .with(headers: { "Content-Type" => "message/rfc822", "Authorization" => expected_auth }, body: email.relayable_raw)
      .to_return(status: 204)

    delivery.deliver

    assert_requested request
    assert_equal "completed", delivery.state
    assert delivery.succeeded?
  end

  test "the relayed body carries the trace headers a relay can't otherwise see" do
    email = inbound_emails(:received)
    email.raw = file_fixture("raw.eml").read
    delivery = relay_webhook.deliveries.create!(event: email.track_event("received"))

    stub_request(:post, relay_webhook.url).to_return(status: 204)

    delivery.deliver

    assert_requested :post, relay_webhook.url do |sent|
      sent.body.start_with?("Delivered-To: inbox@example.com\r\n") &&
        sent.body.include?("X-PostRider-Mailpiece-Id: #{email.mailpiece.id}\r\n") &&
        sent.body.end_with?(email.raw)
    end
  end

  test "deliver posts a Slack message linking back to the mailpiece" do
    email = inbound_emails(:received)
    delivery = slack_webhook.deliveries.create!(event: email.track_event("received", rcpt_to: email.rcpt_to))

    expected_text = "Received inbound mail for inbox@example.com " \
      "<http://example.com#{Current.account.slug}/mailpieces/#{email.mailpiece.id}|Open in PostRider>"

    request = stub_request(:post, slack_webhook.url)
      .with(headers: { "Content-Type" => "application/json" }, body: { text: expected_text }.to_json)
      .to_return(status: 200, body: "ok")

    delivery.deliver

    assert_requested request
    assert_equal "completed", delivery.state
    assert delivery.succeeded?
  end

  test "a Slack message html-escapes special characters" do
    event = domains(:example).track_event("verification_lost", error: %(no TXT record for "example.com" & <root>))
    delivery = slack_webhook.deliveries.create!(event: event)

    captured_body = nil
    stub_request(:post, slack_webhook.url)
      .with { |request| captured_body = request.body; true }
      .to_return(status: 200, body: "ok")

    delivery.deliver

    expected = "DNS verification lost for example.com: no TXT record for &quot;example.com&quot; &amp; &lt;root&gt; " \
      "<http://example.com#{Current.account.slug}/domains/#{domains(:example).id}|Open in PostRider>"
    assert_equal expected, JSON.parse(captured_body)["text"]
  end

  test "deliver completes and records a failure on a non-2xx response" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_return(status: 500)

    tracker = @webhook.delinquency_tracker
    assert_difference -> { tracker.reload.consecutive_failures_count }, 1 do
      delivery.deliver
    end

    assert_equal "completed", delivery.state
    assert_equal 500, delivery.response[:code]
    assert delivery.failed?
  end

  test "a delinquent webhook is deactivated and the deactivation is tracked" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_return(status: 500)
    @webhook.delinquency_tracker.update_columns(consecutive_failures_count: 9, first_failure_at: 2.hours.ago)

    assert_difference -> { Event.count }, 1 do
      delivery.deliver
    end

    assert_not @webhook.reload.active?

    event = @webhook.events.last
    assert_equal "webhook_deactivated", event.action
    assert_equal 10, event.particulars["consecutive_failures_count"]
    assert_equal 500, event.particulars["code"]
  end

  test "a webhook deactivated by hand is not tracked as a delinquency" do
    assert_no_difference -> { Event.count } do
      @webhook.deactivate
    end
  end

  test "deliver maps a timeout to connection_timeout and records a failure" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_timeout

    tracker = @webhook.delinquency_tracker
    assert_difference -> { tracker.reload.consecutive_failures_count }, 1 do
      delivery.deliver
    end

    assert_equal "completed", delivery.state
    assert_equal "connection_timeout", delivery.response[:error]
    assert_not delivery.succeeded?
  end

  test "deliver maps a refused connection to destination_unreachable" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_raise(Errno::ECONNREFUSED)

    tracker = @webhook.delinquency_tracker
    assert_difference -> { tracker.reload.consecutive_failures_count }, 1 do
      delivery.deliver
    end

    assert_equal "destination_unreachable", delivery.response[:error]
  end

  test "deliver maps an SSL error to failed_tls" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_raise(OpenSSL::SSL::SSLError)

    delivery.deliver

    assert_equal "failed_tls", delivery.response[:error]
  end

  test "deliver errors and raises when something unexpected goes wrong" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_raise(StandardError, "Unexpected error")

    assert_raises(StandardError) { delivery.deliver }

    assert_equal "errored", delivery.state
  end

  test "deliver maps a premature EOF to connection_closed_prematurely" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_raise(EOFError)

    delivery.deliver

    assert_equal "connection_closed_prematurely", delivery.response[:error]
  end

  test "deliver blocks a host that resolves to a private IP" do
    delivery = build_delivery
    stub_dns_resolution("169.254.169.254")

    delivery.deliver

    assert_equal "completed", delivery.state
    assert_equal "private_uri", delivery.response[:error]
    assert_not delivery.succeeded?
  end

  test "connects to the pinned IP address even when a proxy is configured" do
    @webhook.update!(url: "http://example.com/webhook")
    delivery = build_delivery

    TCPSocket.expects(:open).with { |*args, **| args.first == "proxy.internal" }.never
    TCPSocket.expects(:open).with { |*args, **| args.first == PUBLIC_TEST_IP && args[1] == 80 }.throws(:not_proxied)

    with_env(http_proxy: "http://proxy.internal:3128", HTTP_PROXY: "http://proxy.internal:3128", no_proxy: nil, NO_PROXY: nil) do
      assert_throws :not_proxied do
        delivery.deliver
      end
    end
  end

  test "deliver rejects an oversized response" do
    delivery = build_delivery
    stub_request(:post, @webhook.url).to_return(status: 200, body: "x" * 200.kilobytes)

    delivery.deliver

    assert_equal "response_too_large", delivery.response[:error]
    assert_not delivery.succeeded?
  end

  test "cleanup deletes stale deliveries and keeps fresh ones" do
    fresh = build_delivery
    stale = @webhook.deliveries.create!(event: deliveries(:queued).track_event("delivered"), created_at: 8.days.ago)

    Webhook::Delivery.cleanup

    assert Webhook::Delivery.exists?(fresh.id)
    assert_not Webhook::Delivery.exists?(stale.id)
  end

  private
    def build_delivery
      @webhook.deliveries.create!(event: @event)
    end

    def relay_webhook
      @relay_webhook ||= domains(:example).webhooks.create!(name: "Relay",
        url: "https://example.com/rails/action_mailbox/relay/inbound_emails",
        subscribed_actions: %w[ inbound_email_received ])
    end

    def slack_webhook
      @slack_webhook ||= domains(:example).webhooks.create!(name: "Slack",
        url: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX",
        subscribed_actions: %w[ inbound_email_received ])
    end
end
