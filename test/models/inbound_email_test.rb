require "test_helper"

class InboundEmailTest < ActiveSupport::TestCase
  test "mail to the account's bounce address is a bounce" do
    Current.account.setting.update!(bounce_address: "bounces@example.com")

    email = create_inbound_email(mail_from: "mailer-daemon@example.com", rcpt_to: "bounces@example.com")

    assert email.to_bounce_address?
  end

  test "mail to the domain's dmarc-reports address is a dmarc report" do
    email = create_inbound_email(mail_from: "noreply-dmarc-support@google.com", rcpt_to: "dmarc-reports@example.com")

    assert email.to_dmarc_reports_address?
  end

  test "mail to any other address is not a dmarc report" do
    assert_not inbound_emails(:received).to_dmarc_reports_address?
  end

  test "the dmarc-reports address is matched regardless of case" do
    email = create_inbound_email(mail_from: "noreply-dmarc-support@google.com", rcpt_to: "DMARC-Reports@Example.com")

    assert email.to_dmarc_reports_address?
  end

  test "forward dispatches inbound_email_received webhooks" do
    webhooks(:active).update!(subscribed_actions: %w[ inbound_email_received ])

    email = create_inbound_email

    assert_difference -> { Event.count }, 1 do
      assert_enqueued_jobs 1, only: Event::WebhookDispatchJob do
        email.forward(ip: "203.0.113.1", helo: "sender.example")
      end
    end

    assert email.delivered?
    assert_equal "inbound_email_received", Event.last.action
  end

  test "forward marks the row processing while it works, then resolves to delivered" do
    email = create_inbound_email
    status_while_tracking = nil

    email.expects(:track_event).with do |_action, **_particulars|
      status_while_tracking = email.reload.status
      true
    end

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    assert_equal "processing", status_while_tracking
    assert email.delivered?
  end

  test "forward delivers a message nested too deep to parse" do
    email = create_inbound_email(raw: deeply_nested_raw)

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    assert email.delivered?
    assert_not email.attachments.attached?
  end

  test "processed? is true only once the mail reaches a terminal state" do
    email = create_inbound_email

    assert email.pending?
    assert_not email.processed?

    email.update!(status: :processing)
    assert_not email.processed?

    email.update!(status: :delivered)
    assert email.processed?

    email.update!(status: :failed)
    assert email.processed?

    email.update!(status: :bounced)
    assert email.processed?
  end

  test "discard delivers no webhook, because nothing subscribes to a discard" do
    webhooks(:active).update!(subscribed_actions: %w[ inbound_email_received ])

    email = create_inbound_email(rcpt_to: "randomjunk@example.com")

    assert_no_difference -> { Webhook::Delivery.count } do
      perform_enqueued_jobs only: Event::WebhookDispatchJob do
        email.discard
      end
    end

    assert email.bounced?
    assert email.forwarded_at.present?
  end

  test "forward tracks the receipt, kept out of the feed so ordinary mail cannot flood it" do
    email = create_inbound_email(rcpt_to: "list@example.com")

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    event = email.events.last
    assert_equal "inbound_email_received", event.action
    assert_equal "list@example.com", event.particulars["rcpt_to"]
    assert_empty email.events.notable
  end

  test "forward records the client address and its confirmed name on the receipt event" do
    stub_mailauth(iprev: "pass", remote_host: "mail.sender.example")
    email = create_inbound_email

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    event = email.events.last
    assert_equal "203.0.113.1", event.particulars["remote_ip"]
    assert_equal "mail.sender.example", event.particulars["remote_host"]
    assert_equal "pass", email.iprev
  end

  test "forward records the receipt without a name when none resolved back" do
    stub_mailauth(iprev: "fail")
    email = create_inbound_email

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    event = email.events.last
    assert_equal "203.0.113.1", event.particulars["remote_ip"]
    assert_not event.particulars.key?("remote_host")
  end

  test "forward tracks a bounce receipt as its own action" do
    Current.account.setting.update!(bounce_address: "bounces@example.com")
    email = create_inbound_email(mail_from: "mailer-daemon@remote.com", rcpt_to: "bounces@example.com", raw: "Subject: DSN\r\n\r\nFailed")

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    assert_equal "inbound_email_bounce_received", email.events.last.action
  end

  test "discard tracks why the mail was discarded" do
    email = create_inbound_email(rcpt_to: "randomjunk@example.com")

    email.discard

    event = email.events.last
    assert_equal "inbound_email_discarded", event.action
    assert_equal "unregistered_recipient", event.particulars["reason"]
    assert_equal "randomjunk@example.com", event.particulars["rcpt_to"]
  end

  test "fail_permanently tracks why the mail was never forwarded" do
    email = create_inbound_email

    email.fail_permanently(reason: "forwarding_failed")

    assert email.failed?
    event = email.events.last
    assert_equal "inbound_email_failed", event.action
    assert_equal "forwarding_failed", event.particulars["reason"]
  end

  test "raw is stored as an attached rfc822 blob and round-trips the exact bytes" do
    raw = "Subject: hi\r\n\r\nBody"
    email = create_inbound_email(raw: raw)

    assert email.raw_email.attached?
    assert_equal "message/rfc822", email.raw_email.content_type
    assert_equal raw, InboundEmail.find(email.id).raw
  end

  test "subject is persisted when raw is assigned" do
    email = create_inbound_email(raw: "Subject: hi\r\n\r\nhello world")

    assert_equal "hi", email[:subject]
    assert_equal "hi", InboundEmail.find(email.id).subject
  end

  test "write-time summary parsing does not require the full message body" do
    huge_attachment = Base64.strict_encode64("x" * 300.kilobytes)
    raw = "Subject: big\r\nContent-Type: multipart/mixed; boundary=b\r\n\r\n" \
      "--b\r\nContent-Type: text/plain\r\n\r\nhello\r\n" \
      "--b\r\nContent-Type: application/octet-stream\r\nContent-Transfer-Encoding: base64\r\n\r\n" \
      "#{huge_attachment}\r\n--b--\r\n"

    email = create_inbound_email(raw: raw)

    assert_equal "big", email[:subject]
    assert email.raw_email.attached?
    assert_equal raw.bytesize, email.raw_email.byte_size
  end

  test "a mail without a subject persists an empty string so it is never reparsed" do
    email = create_inbound_email(raw: "From: a@example.com\r\n\r\nno subject here")

    assert_equal "", email[:subject]
    assert_equal "", InboundEmail.find(email.id).subject
  end

  test "incinerate_all_due strips the raw email attachment and blob but keeps the row and its metadata" do
    email = create_inbound_email(raw: "Subject: old\r\n\r\nBody")
    email.update!(status: :delivered, forwarded_at: 31.days.ago)

    assert_difference -> { ActiveStorage::Attachment.count } => -1, -> { ActiveStorage::Blob.count } => -1 do
      InboundEmail.incinerate_all_due
    end

    assert InboundEmail.exists?(email.id)
    assert email.reload.incinerated?
    assert_not email.raw_email.attached?
    assert_equal "old", email.subject
  end

  test "incinerate_all_due keeps a shared blob alive while another recipient's copy of the message survives" do
    incinerable, kept = recipients_sharing_one_message
    incinerable.update!(status: :delivered, forwarded_at: 31.days.ago)

    assert_difference -> { ActiveStorage::Attachment.count } => -1, -> { ActiveStorage::Blob.count } => 0 do
      InboundEmail.incinerate_all_due
    end

    assert incinerable.reload.incinerated?
    blob = kept.reload.raw_email.blob
    assert blob.service.exist?(blob.key)
    assert_equal "Subject: Fanout\r\n\r\nBody.", kept.raw
  end

  test "incinerate_all_due strips a shared blob and its file once the last recipient's copy goes" do
    one, two = recipients_sharing_one_message
    blob = one.raw_email.blob
    [ one, two ].each { |email| email.update!(status: :delivered, forwarded_at: 31.days.ago) }

    assert_difference -> { ActiveStorage::Attachment.count } => -2, -> { ActiveStorage::Blob.count } => -1 do
      InboundEmail.incinerate_all_due
    end

    assert one.reload.incinerated?
    assert two.reload.incinerated?
    assert_not blob.service.exist?(blob.key)
  end

  test "incinerate_all_due keeps the events of the rows it incinerates and records an incineration event" do
    old_delivered = create_inbound_email
    old_delivered.track_event("received", rcpt_to: old_delivered.rcpt_to)
    old_delivered.update!(status: :delivered, forwarded_at: 31.days.ago)

    InboundEmail.incinerate_all_due

    actions = old_delivered.events.pluck(:action)
    assert_includes actions, "inbound_email_received"
    assert_includes actions, "inbound_email_incinerated"
  end

  test "incinerate_all_due incinerates both delivered and bounced rows past the retention window, and nothing else" do
    old_delivered = create_inbound_email
    old_delivered.update!(status: :delivered, forwarded_at: 31.days.ago)

    old_bounced = create_inbound_email
    old_bounced.update!(status: :bounced, forwarded_at: 31.days.ago)

    recent_bounced = create_inbound_email
    recent_bounced.update!(status: :bounced, forwarded_at: 1.hour.ago)

    pending = create_inbound_email

    processing = create_inbound_email
    processing.update!(status: :processing)
    processing.update_column(:created_at, 31.days.ago)

    InboundEmail.incinerate_all_due

    assert old_delivered.reload.incinerated?
    assert old_bounced.reload.incinerated?
    assert_not recent_bounced.reload.incinerated?
    assert_not pending.reload.incinerated?
    assert_not processing.reload.incinerated?, "an in-flight processing row is never incinerated"
  end

  test "incinerate_all_due incinerates failed rows only after a 30-day retention" do
    old_failed = create_inbound_email
    old_failed.update!(status: :failed)
    old_failed.update_column(:created_at, 31.days.ago)

    recent_failed = create_inbound_email
    recent_failed.update!(status: :failed)
    recent_failed.update_column(:created_at, 8.days.ago)

    InboundEmail.incinerate_all_due

    assert old_failed.reload.incinerated?
    assert_not recent_failed.reload.incinerated?
  end

  test "incinerate_all_due keys a delivered row's retention off forwarded_at, not its older created_at" do
    recently_forwarded = create_inbound_email
    recently_forwarded.update!(status: :delivered, forwarded_at: 1.hour.ago)
    recently_forwarded.update_column(:created_at, 31.days.ago)

    InboundEmail.incinerate_all_due

    assert_not recently_forwarded.reload.incinerated?, "a delivered row forwarded within the window is kept even when created long ago"
  end

  test "fail_abandoned fails pending and stuck processing emails older than a day and reports them, leaving everything else alone" do
    abandoned = create_inbound_email
    abandoned.update_column(:created_at, 2.days.ago)

    stuck_processing = create_inbound_email
    stuck_processing.update!(status: :processing)
    stuck_processing.update_column(:created_at, 2.days.ago)

    fresh_pending = create_inbound_email

    old_delivered = inbound_emails(:received)
    old_delivered.update!(forwarded_at: 2.days.ago)
    old_delivered.update_column(:created_at, 2.days.ago)

    Rails.error.expects(:report).with(instance_of(InboundEmail::Abandoned), severity: :error).twice

    InboundEmail.fail_abandoned

    assert abandoned.reload.failed?
    assert stuck_processing.reload.failed?
    assert fresh_pending.reload.pending?
    assert old_delivered.reload.delivered?
  end

  test "forwards a multi-megabyte inbound email (payload is rendered, not stored in a 64KB column)" do
    body = "x" * 10.megabytes
    big_raw = "Subject: Photos\r\n\r\n" + body
    email = create_inbound_email(raw: big_raw)

    assert_nothing_raised { email.forward(ip: "203.0.113.1", helo: "sender.example") }
    assert email.reload.delivered?

    assert_includes email.webhook_payload("inbound_email_received")[:text], body
  end

  test "forward extracts attachments before it records the receipt event" do
    email = create_inbound_email(raw: raw_with_attachment)
    attached_when_tracked = nil

    email.expects(:track_event).with do |_action, **_particulars|
      attached_when_tracked = email.attachments.attached?
      true
    end

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    assert attached_when_tracked, "attachments must be extracted before the receipt event is tracked"
  end

  test "the receipt event's webhook payload describes the extracted attachments" do
    email = create_inbound_email(raw: raw_with_attachment)

    email.forward(ip: "203.0.113.1", helo: "sender.example")

    payload = email.webhook_payload("inbound_email_received")
    assert_equal "photo.jpg", payload[:attachments].sole[:filename]
    assert_equal "image/jpeg", payload[:attachments].sole[:contentType]
  end

  test "nothing is a bounce until the account configures a bounce address" do
    assert_not inbound_emails(:received).to_bounce_address?
  end

  test "another account's bounce address does not classify this account's mail" do
    accounts(:other_account).setting.update!(bounce_address: inbound_emails(:received).rcpt_to)

    assert_not inbound_emails(:received).to_bounce_address?
  end

  private
    def raw_with_attachment
      <<~EOM
        From: a@example.com
        To: list@example.com
        Subject: With attachment
        Content-Type: multipart/mixed; boundary=MIX

        --MIX
        Content-Type: text/plain

        see attached
        --MIX
        Content-Type: image/jpeg; name="photo.jpg"
        Content-Disposition: attachment; filename="photo.jpg"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64("jpeg bytes")}
        --MIX--
      EOM
    end

    def recipients_sharing_one_message
      source = Sourced::Source.new("Subject: Fanout\r\n\r\nBody.")

      %w[ one@example.com two@example.com ].map do |rcpt_to|
        InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: rcpt_to, source: source, digest: "fanout")
      end
    end
end
