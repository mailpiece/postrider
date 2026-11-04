require "test_helper"

class Domain::PurgeMailJobTest < ActiveJob::TestCase
  setup do
    @domain = domains(:example)
  end

  test "removes a removed domain's mail, its history and its stored mail" do
    delivery = create_delivery(raw: "Subject: Out\r\n\r\nBody")
    delivery.attempts.create!(code: "250", output: "250 2.0.0 OK", mx_host: "mx.recipient.example")
    pause = Pause.create!(provider: "example-provider", recipient_domain: "recipient.example", delivery:)
    webhook_delivery = webhooks(:active).deliveries.create!(event: delivery.track_event("delivered", rcpt_to: delivery.rcpt_to))
    sending_tokens(:example).idempotent_requests.create!(key: "k", message: delivery.message)
    incinerated = [ create_delivery.message, create_inbound_email ].each(&:incinerate)
    inbound_email = create_inbound_email(raw: "Subject: In\r\n\r\nBody")
    blob_ids = ActiveStorage::Attachment.where(record: [ delivery.message, inbound_email ]).pluck(:blob_id)

    @domain.destroy!
    purge_mail

    assert_empty Message.where(domain_id: @domain.id)
    assert_empty Delivery.where(domain_id: @domain.id)
    assert_empty InboundEmail.where(domain_id: @domain.id)
    assert_empty Mailpiece.where(domain_id: @domain.id)
    assert_empty Event.where(domain_id: @domain.id)
    assert_empty Delivery::Attempt.where(delivery_id: delivery.id)
    assert_empty Incineration.where(incinerable: incinerated)
    assert_empty IdempotentRequest.where(message_id: delivery.message_id)
    assert_not Webhook::Delivery.exists?(webhook_delivery.id)
    assert_empty ActiveStorage::Blob.where(id: blob_ids)
    assert_nil pause.reload.delivery_id
  end

  test "leaves another domain's mail, events and webhook deliveries alone" do
    create_delivery
    theirs = deliver_from(domains(:private))
    their_webhook = domains(:private).webhooks.create!(name: "Theirs", url: "https://hooks.example.com/private", subscribed_actions: %w[ delivery_delivered ])
    their_webhook_delivery = their_webhook.deliveries.create!(event: theirs.track_event("delivered", rcpt_to: theirs.rcpt_to))
    their_inbound_email = create_inbound_email(domain: domains(:private))

    @domain.destroy!
    purge_mail

    assert theirs.reload.mailpiece.present?
    assert theirs.message.raw_email.attached?
    assert theirs.events.exists?
    assert Webhook::Delivery.exists?(their_webhook_delivery.id)
    assert InboundEmail.find(their_inbound_email.id).raw.present?
  end

  test "keeps a stored message another domain's inbound mail shares" do
    source = Sourced::Source.new("Subject: Fanout\r\n\r\nBody.")
    create_inbound_email(raw: nil, source:, digest: "shared")
    theirs = create_inbound_email(domain: domains(:private), rcpt_to: "c@example.com", raw: nil, source:, digest: "shared")

    @domain.destroy!
    purge_mail

    assert_equal "Subject: Fanout\r\n\r\nBody.", InboundEmail.find(theirs.id).raw
  end

  test "running twice is fine" do
    create_delivery
    @domain.destroy!

    purge_mail
    purge_mail

    assert_empty Message.where(domain_id: @domain.id)
  end

  test "sweeps what a delivery or an SMTP session in flight wrote after the domain went" do
    delivery = create_delivery
    @domain.destroy!
    purge_mail

    late_inbound_email = create_inbound_email(domain: @domain)
    late_event = Event.create!(eventable: delivery, domain: @domain, account: @domain.account, action: "delivery_delivered")
    purge_mail

    assert_not InboundEmail.exists?(late_inbound_email.id)
    assert_not Event.exists?(late_event.id)
    assert_empty Mailpiece.where(domain_id: @domain.id)
  end

  private
    def purge_mail
      Domain::PurgeMailJob.perform_now(@domain.id)
      perform_enqueued_jobs only: ActiveStorage::PurgeJob
    end
end
