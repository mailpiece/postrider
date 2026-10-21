require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    @delivery = deliveries(:queued)
  end

  test "particulars round-trip as a hash" do
    event = @delivery.track_event("thing", foo: "bar")

    assert_equal "bar", event.reload.particulars["foo"]
  end

  test "ordered returns newest first" do
    older = @delivery.track_event("thing")
    newer = @delivery.track_event("thing")

    assert_equal [ newer, older ], @delivery.events.ordered.to_a
  end

  test "notable keeps everything but successful deliveries, which stay on the delivery itself" do
    delivered = @delivery.track_event("delivered", rcpt_to: @delivery.rcpt_to)
    bounced = @delivery.track_event("bounced", rcpt_to: @delivery.rcpt_to)

    assert_equal [ bounced ], @delivery.events.notable.to_a
    assert_includes @delivery.events, delivered
  end

  test "bounced covers both intakes and nothing else" do
    bounced = @delivery.track_event("bounced", rcpt_to: @delivery.rcpt_to)
    @delivery.track_event("delivered", rcpt_to: @delivery.rcpt_to)

    assert_equal [ bounced ], Event.bounced.to_a
  end

  test "particulars carrying raw bytes from a remote server are scrubbed, not dropped" do
    binary_dsn = "550 no such user \xE9\xFF".dup.force_encoding(Encoding::BINARY)

    event = @delivery.track_event("bounced", rcpt_to: @delivery.rcpt_to, dsn: binary_dsn)

    assert_not_nil event, "a bounce carrying non-UTF-8 bytes must still be recorded, or its webhook never fires"
    assert_equal Encoding::UTF_8, event.reload.particulars["dsn"].encoding
    assert_match "550 no such user", event.particulars["dsn"]
  end

  test "an event delivers itself to the webhooks subscribed to its action" do
    webhook = webhooks(:active)

    assert_difference -> { webhook.deliveries.count }, 1 do
      perform_enqueued_jobs only: Event::WebhookDispatchJob do
        @delivery.track_event("delivered", rcpt_to: @delivery.rcpt_to)
      end
    end

    assert_equal "delivery_delivered", webhook.deliveries.last.event.action
  end

  test "a sending token event's body carries the domain, the token's name and the refused IP" do
    domain = domains(:example)
    event = Event.create!(eventable: domain, domain: domain, action: "sending_token_refused", particulars: { token_name: "Production", ip: "181.110.44.220" })

    assert_equal({ "event" => "sending_token_refused", "payload" => { "domain_id" => domain.id, "domain" => "example.com", "token_name" => "Production", "ip" => "181.110.44.220" } },
      JSON.parse(event.body))
  end

  test "creating and revoking a sending token send bodies with its name" do
    token = domains(:example).sending_tokens.create!(name: "Production")
    token.destroy!

    %w[ sending_token_created sending_token_revoked ].each do |action|
      body = JSON.parse(domains(:example).events.find_by!(action: action).body)
      assert_equal action, body["event"]
      assert_equal "Production", body["payload"]["token_name"]
    end
  end

  test "purging an event takes its webhook deliveries with it" do
    event = @delivery.track_event("delivered", rcpt_to: @delivery.rcpt_to)
    delivery = webhooks(:active).deliveries.create!(event: event)

    Event.purge Event.where(id: event.id)

    assert_not Webhook::Delivery.exists?(delivery.id)
    assert_empty Webhook::Delivery.where.missing(:event)
  end

  test "notable ignores actions it does not know about" do
    @delivery.track_event("thing")

    assert_empty @delivery.events.notable
  end

  test "a tracking failure raises" do
    Event.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_raises(ActiveRecord::RecordInvalid) { @delivery.track_event("thing") }
  end
end
