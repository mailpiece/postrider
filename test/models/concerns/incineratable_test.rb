require "test_helper"

class IncineratableTest < ActiveSupport::TestCase
  test "incinerate destroys the raw content and its attachments while keeping the row and its metadata" do
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: raw_with_attachment)
    email.forward(ip: "203.0.113.1", helo: "sender.example")
    assert email.attachments.attached?

    assert_difference -> { ActiveStorage::Blob.count } => -2 do
      email.incinerate
    end

    assert InboundEmail.exists?(email.id)
    assert email.reload.incinerated?
    assert_not_nil email.incinerated_at
    assert_not email.raw_email.attached?
    assert_not email.attachments.attached?
    assert_equal "b@example.com", email.rcpt_to
  end

  test "incinerate creates exactly one incineration record for the row" do
    email = create_inbound_email

    assert_difference -> { Incineration.count } => 1 do
      email.incinerate
    end

    assert_kind_of Incineration, email.incineration
    assert_equal email, email.incineration.incinerable
  end

  test "incinerate records an incineration event carrying the eventable prefix and keeps prior events" do
    email = create_inbound_email
    email.track_event("received", rcpt_to: email.rcpt_to)

    email.incinerate

    actions = email.events.pluck(:action)
    assert_includes actions, "inbound_email_received"
    assert_includes actions, "inbound_email_incinerated"
  end

  test "a message records a message_incinerated event" do
    message = domains(:example).messages.create!(mail_from: "a@example.com", raw: "Subject: hi\r\n\r\nBody")

    message.incinerate

    assert_equal "message_incinerated", message.events.pluck(:action).last
    assert message.reload.incinerated?
  end

  test "incinerate is idempotent, leaving a second call a no-op" do
    email = create_inbound_email
    email.incinerate
    incinerated_at = email.reload.incinerated_at

    assert_no_difference [ -> { Incineration.count }, -> { ActiveStorage::Blob.count }, -> { email.events.count } ] do
      email.incinerate
    end

    assert_equal incinerated_at, email.reload.incinerated_at
  end

  test "a row cannot be incinerated twice at the record level" do
    email = inbound_emails(:received)
    Incineration.create!(incinerable: email)

    assert_raises ActiveRecord::RecordNotUnique do
      Incineration.create!(incinerable: email)
    end
  end

  test "deleting the parent destroys its incineration" do
    email = create_inbound_email
    email.incinerate
    incineration = email.incineration

    email.destroy!

    assert_not Incineration.exists?(incineration.id)
  end

  test "the incinerated and incineratable scopes partition rows by their incineration" do
    incinerated = create_inbound_email
    incinerated.incinerate
    live = inbound_emails(:held)

    assert_includes InboundEmail.incinerated, incinerated
    assert_not_includes InboundEmail.incinerated, live
    assert_includes InboundEmail.incineratable, live
    assert_not_includes InboundEmail.incineratable, incinerated
  end

  private
    def raw_with_attachment
      <<~EOM
        From: a@example.com
        To: b@example.com
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
end
