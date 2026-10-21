require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  test "requires a name" do
    webhook = domains(:example).webhooks.build(url: "https://example.com/hooks")
    assert_not webhook.valid?
    assert_includes webhook.errors[:name], "can't be blank"
  end

  test "a webhook is not triggered by another domain's event" do
    theirs = domains(:private).webhooks.create!(name: "Theirs", url: "https://example.com/theirs",
      subscribed_actions: %w[ delivery_delivered ])

    triggered = Webhook.active.triggered_by(deliveries(:delivered).track_event("delivered"))

    assert_includes triggered, webhooks(:active)
    assert_not_includes triggered, theirs
  end

  test "the same address may be subscribed once per domain" do
    assert domains(:private).webhooks.build(name: webhooks(:active).name, url: webhooks(:active).url,
      subscribed_actions: webhooks(:active).subscribed_actions).valid?
  end

  test "rejects a non-http(s) url" do
    webhook = domains(:example).webhooks.build(name: "Bad", url: "ftp://example.com")
    assert_not webhook.valid?
    assert_includes webhook.errors[:url], "must use http or https"
  end

  test "keeps only permitted subscribed actions" do
    webhook = domains(:example).webhooks.create!(name: "Filtered", url: "https://example.com/h",
      subscribed_actions: %w[ inbound_email_received bogus_action ])
    assert_equal %w[ inbound_email_received ], webhook.subscribed_actions
  end

  test "generates a signing secret and a delinquency tracker on create" do
    webhook = domains(:example).webhooks.create!(name: "Fresh", url: "https://example.com/h")
    assert webhook.signing_secret.present?
    assert webhook.delinquency_tracker.present?
  end

  test "for_action_mailbox_relay? matches the Action Mailbox relay ingress URL" do
    webhook = domains(:example).webhooks.build(name: "Relay",
      url: "https://example.com/rails/action_mailbox/relay/inbound_emails")
    assert webhook.for_action_mailbox_relay?

    webhook.url = "https://example.com/hooks"
    assert_not webhook.for_action_mailbox_relay?
  end

  test "for_slack? matches a Slack incoming webhook URL" do
    webhook = domains(:example).webhooks.build(name: "Slack",
      url: "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX")
    assert webhook.for_slack?

    webhook.url = "https://example.com/hooks/slack"
    assert_not webhook.for_slack?
  end

  test "rejects subscribed actions other than inbound_email_received/inbound_email_bounce_received for an Action Mailbox relay URL" do
    webhook = domains(:example).webhooks.build(name: "Relay",
      url: "https://example.com/rails/action_mailbox/relay/inbound_emails",
      subscribed_actions: %w[ inbound_email_received delivery_delivered ])

    assert_not webhook.valid?
    assert_includes webhook.errors[:subscribed_actions],
      "can only include inbound_email_received and inbound_email_bounce_received when the URL points at an Action Mailbox relay ingress"
  end

  test "allows inbound_email_received and inbound_email_bounce_received for an Action Mailbox relay URL" do
    webhook = domains(:example).webhooks.create!(name: "Relay",
      url: "https://example.com/rails/action_mailbox/relay/inbound_emails",
      subscribed_actions: %w[ inbound_email_received inbound_email_bounce_received ])

    assert webhook.valid?
  end

  test "triggered_by matches a subscribed action" do
    assert_includes Webhook.triggered_by(deliveries(:delivered).track_event("delivered")), webhooks(:active)
  end

  test "trigger creates a delivery" do
    event = deliveries(:delivered).track_event("delivered")

    assert_difference -> { webhooks(:active).deliveries.count }, 1 do
      webhooks(:active).trigger(event)
    end
  end

  test "trigger is idempotent for the same event" do
    event = deliveries(:delivered).track_event("delivered")

    assert_difference -> { webhooks(:active).deliveries.count }, 1 do
      2.times { webhooks(:active).trigger(event) }
    end
  end

  test "trigger skips a cancelled account" do
    event = deliveries(:delivered).track_event("delivered")
    accounts(:davids_account).cancel(initiated_by: users(:leo))

    assert_no_difference -> { Webhook::Delivery.count } do
      webhooks(:active).trigger(event)
    end
  end
end
