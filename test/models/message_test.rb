require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "from_name adds a display name to a plain from address" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", from_name: "Example List",
      to: [ "b@example.com" ], subject: "hi", text: "hello")

    assert message.persisted?
    assert_equal "a@example.com", message.mail_from
    assert_includes message.raw, "From: Example List <a@example.com>"
  end

  test "from may use a display name in RFC 5322 form" do
    message = Message.submit(domain: domains(:example), from: "Example List <a@example.com>",
      to: [ "b@example.com" ], subject: "hi", text: "hello")

    assert_includes message.raw, "From: Example List <a@example.com>"
  end

  test "to entries may use display names in RFC 5322 form" do
    message = Message.submit(domain: domains(:example), from: "a@example.com",
      to: [ "Bob <b@example.com>" ], subject: "hi", text: "hello")

    assert_equal [ "b@example.com" ], message.deliveries.pluck(:rcpt_to)
    assert_includes message.raw, "To: Bob <b@example.com>"
  end

  test "reply_to accepts a display name" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      reply_to: "replies@example.com", reply_to_name: "Replies", subject: "hi", text: "hello")

    assert_includes message.raw, "Reply-To: Replies <replies@example.com>"
  end

  test "custom headers are added to the raw message" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      headers: { "X-Entity-Ref-ID" => "abc-123" })

    assert_includes message.raw, "X-Entity-Ref-ID: abc-123"
  end

  test "the Message-ID domain is the sender's domain, not the host's own hostname" do
    message = Message.submit(domain: domains(:example), from: "alice@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello")

    assert_match(/^Message-ID: <[^@]+@example\.com>/, message.raw)
    assert_equal "example.com", Mail.new(message.raw).message_id.split("@").last
  end

  test "a header value cannot inject a stray header line via embedded CRLF" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      headers: { "X-Custom" => "value\r\nBcc: attacker@evil.example" })

    assert message.persisted?
    assert_not message.raw.match?(/^Bcc:/i)
  end

  test "forbidden custom headers are rejected" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      headers: { "Subject" => "override" })

    assert_not message.persisted?
    assert_includes message.errors[:headers], "cannot override Subject"
  end

  # Receiver verdict headers; forging them through the API would claim a judgement we never earned.
  test "a receiver's verdict headers cannot be forged through custom headers" do
    %w[ Authentication-Results Received-SPF ARC-Seal ARC-Message-Signature ARC-Authentication-Results ].each do |name|
      message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
        headers: { name => "forged.example; dkim=pass header.i=@victim.example" })

      assert_not message.persisted?, "expected #{name} to be refused"
      assert_includes message.errors[:headers], "cannot override #{name}"
    end
  end

  test "a custom List-Unsubscribe cannot be smuggled alongside the parameter" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      list_unsubscribe: "<https://example.com/u/abc>", headers: { "List-Unsubscribe" => "<mailto:stale@example.com>" })

    assert_not message.persisted?
    assert_includes message.errors[:headers], "cannot override List-Unsubscribe"
  end

  test "a Sender header cannot be used to spoof a different sending identity" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      headers: { "Sender" => "ceo@othercompany.example" })

    assert_not message.persisted?
    assert_includes message.errors[:headers], "cannot override Sender"
  end

  test "envelope_from sets a separate SMTP MAIL FROM address" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      envelope_from: "bounces@example.com")

    assert_equal "bounces@example.com", message.smtp_envelope_from
    assert_equal "a@example.com", message.mail_from
  end

  test "return_path is an alias for envelope_from" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      return_path: "bounces@example.com")

    assert_equal "bounces@example.com", message.smtp_envelope_from
  end

  test "envelope_from wins over return_path when both are given" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      envelope_from: "envelope@example.com", return_path: "return@example.com")

    assert_equal "envelope@example.com", message.smtp_envelope_from
  end

  test "an empty envelope_from is a null return path" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      envelope_from: "")

    assert_equal "", message.smtp_envelope_from
  end

  test "an omitted envelope_from falls back to the From address" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello")

    assert_equal "a@example.com", message.smtp_envelope_from
  end

  test "in_reply_to and references are set as their own headers" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      in_reply_to: "<parent@example.com>", references: "<grandparent@example.com> <parent@example.com>")

    assert_includes message.raw, "In-Reply-To: <parent@example.com>"
    assert_includes message.raw.gsub(/\r\n /, " "), "References: <grandparent@example.com> <parent@example.com>"
  end

  test "in_reply_to and references are omitted when absent" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello")

    assert_not_includes message.raw, "In-Reply-To"
    assert_not_includes message.raw, "References"
  end

  test "custom headers cannot override in_reply_to or references" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      headers: { "In-Reply-To" => "<spoofed@example.com>" })

    assert_not message.persisted?
    assert_includes message.errors[:headers], "cannot override In-Reply-To"
  end

  test "tags are stored on the message but not embedded in the raw source" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      tags: [ "welcome", "onboarding", "welcome" ])

    assert message.persisted?
    assert_equal %w[ welcome onboarding ], message.tags
    assert_not_includes message.raw, "welcome"
  end

  test "submit rejects more than the max tags" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      tags: (1..Message::MAX_TAGS + 1).map { |i| "tag#{i}" })

    assert_not message.persisted?
    assert_includes message.errors[:tags], "accepts at most #{Message::MAX_TAGS} entries"
  end

  test "submit persists nothing when delivery creation raises" do
    Delivery.any_instance.stubs(:save!).raises(StandardError, "boom")

    assert_no_difference [ -> { Message.count }, -> { Delivery.count } ] do
      assert_raises(StandardError) do
        Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello")
      end
    end
  end

  test "submit builds a plain-text message and delivers to every to/cc recipient" do
    message = nil

    assert_enqueued_jobs 2, only: Delivery::DeliverJob do
      message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], cc: [ "c@example.com" ],
        subject: "hi", text: "hello")
    end

    assert message.persisted?
    assert_equal "a@example.com", message.mail_from
    assert_equal %w[ b@example.com c@example.com ], message.deliveries.pluck(:rcpt_to).sort
    assert_includes message.raw, "Subject: hi"
    assert_includes message.raw, "hello"
  end

  test "bcc recipients receive the message but never appear in the raw source" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], bcc: [ "secret@example.com" ],
      subject: "hi", text: "hello")

    assert_equal %w[ b@example.com secret@example.com ], message.deliveries.pluck(:rcpt_to).sort
    assert_not_includes message.raw, "secret@example.com"
  end

  test "an html body alongside text produces a multipart/alternative message" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi",
      text: "hello", html: "<p>hello</p>")

    assert_includes message.raw, "multipart/alternative"
    assert_includes message.raw, "<p>hello</p>"
    assert_includes message.raw, "hello\r\n"
  end

  test "a text body declares its charset, alone or beside html" do
    alone = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "señor")
    beside = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi",
      text: "señor", html: "<p>señor</p>")

    assert_no_match(/charset defined/, capture_io { Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "señor") }.join)

    [ Mail.new(alone.raw), Mail.new(beside.raw).text_part ].each do |part|
      assert_equal "UTF-8", part.charset
      assert_equal "señor", part.decoded
    end
  end

  test "an html-only message is accepted without a text part" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", html: "<p>hello</p>")

    assert message.persisted?
    assert_includes message.raw, "text/html"
    assert_not_includes message.raw, "multipart"
  end

  test "subject is optional" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello")

    assert message.persisted?
    assert_not_includes message.raw, "Subject:"
  end

  test "a list_unsubscribe value is set as a List-Unsubscribe header" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      list_unsubscribe: "<mailto:list@example.com?subject=unsubscribe>")

    assert_includes message.raw, "List-Unsubscribe: <mailto:list@example.com?subject=unsubscribe>"
  end

  test "an https list_unsubscribe enables RFC 8058 one-click unsubscribe" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      list_unsubscribe: "<https://example.com/u/abc>")

    assert_includes message.raw, "List-Unsubscribe: <https://example.com/u/abc>"
    assert_includes message.raw, "List-Unsubscribe-Post: List-Unsubscribe=One-Click"
  end

  test "a mailto-only list_unsubscribe does not enable one-click unsubscribe" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      list_unsubscribe: "<mailto:unsub@example.com>")

    assert_includes message.raw, "List-Unsubscribe: <mailto:unsub@example.com>"
    assert_not_includes message.raw, "List-Unsubscribe-Post"
  end

  # Bare URLs lack RFC 2369 angle brackets and may be ignored by receivers.
  test "a bare list_unsubscribe URL is bracketed rather than emitted as written" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      list_unsubscribe: "https://example.com/unsubscribe")

    assert_includes message.raw, "List-Unsubscribe: <https://example.com/unsubscribe>"
    assert_includes message.raw, "List-Unsubscribe-Post: List-Unsubscribe=One-Click"
  end

  # One-Click needs a POST target; a mailto query mentioning https has none.
  test "a mailto list_unsubscribe mentioning https does not enable one-click unsubscribe" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello",
      list_unsubscribe: "<mailto:unsub@example.com?body=see%20https://example.com/help>")

    assert_includes message.raw, "List-Unsubscribe: <mailto:unsub@example.com"
    assert_not_includes message.raw, "List-Unsubscribe-Post"
  end

  test "a message without list_unsubscribe carries neither List-Unsubscribe header" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello")

    assert_not_includes message.raw, "List-Unsubscribe"
  end

  test "submit rejects a message with no recipients at all and creates no deliveries" do
    message = nil

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      message = Message.submit(domain: domains(:example), from: "a@example.com", to: [], text: "hello")
    end

    assert_not message.persisted?
    assert_includes message.errors[:base], "needs at least one recipient in to, cc, or bcc"
  end

  test "submit accepts up to the max recipients across to, cc, and bcc" do
    message = Message.submit(domain: domains(:example), from: "a@example.com",
      to: (1..Message::MAX_RECIPIENTS).map { |i| "r#{i}@example.com" }, text: "hello")

    assert message.persisted?
    assert_equal Message::MAX_RECIPIENTS, message.deliveries.count
  end

  test "submit rejects more than the max recipients and creates no deliveries" do
    message = nil

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      message = Message.submit(domain: domains(:example), from: "a@example.com",
        to: (1..Message::MAX_RECIPIENTS + 1).map { |i| "r#{i}@example.com" }, text: "hello")
    end

    assert_not message.persisted?
    assert_includes message.errors[:base], "accepts at most #{Message::MAX_RECIPIENTS} recipients across to, cc, and bcc"
  end

  test "submit rejects a message with neither text nor html" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ])

    assert_not message.persisted?
    assert_includes message.errors[:base], "needs a text or html"
  end

  test "submit rejects a message over the max size and creates no deliveries" do
    oversized = "x" * (Relay.max_outbound_message_size + 1)
    message = nil

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: oversized)
    end

    assert_not message.persisted?
    assert_includes message.errors[:raw], "is too large"
  end

  test "an attachment is embedded as a proper multipart/mixed sibling, not folded into the alternative" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      attachments: [ { name: "test.txt", content_type: "text/plain", content: Base64.strict_encode64("attachment bytes") } ])

    assert message.persisted?
    parsed = Mail.new(message.raw)
    assert_equal "multipart/mixed", parsed.mime_type
    assert_equal 1, parsed.attachments.count
    assert_equal "attachment bytes", parsed.attachments.first.body.decoded
    assert_includes message.raw, "hello"
  end

  test "an attachment alongside both text and html nests a proper multipart/alternative" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi",
      text: "hello", html: "<p>hello</p>",
      attachments: [ { name: "test.txt", content_type: "text/plain", content: Base64.strict_encode64("attachment bytes") } ])

    parsed = Mail.new(message.raw)
    assert_equal "multipart/mixed", parsed.mime_type
    assert_includes message.raw, "multipart/alternative"
    assert_includes message.raw, "<p>hello</p>"
    assert_equal 1, parsed.attachments.count
  end

  test "malformed attachment parameters are rejected" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      attachments: "not-an-array")

    assert_not message.persisted?
    assert_includes message.errors[:attachments], "are invalid"
  end

  test "an attachment with invalid base64 is rejected" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      attachments: [ { name: "test.txt", content_type: "text/plain", content: "%%%not-base64%%%" } ])

    assert_not message.persisted?
    assert_includes message.errors[:attachments], "are invalid"
  end

  test "an attachment with an unsupported extension is rejected" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      attachments: [ { name: "malware.exe", content_type: "application/octet-stream", content: Base64.strict_encode64("x") } ])

    assert_not message.persisted?
    assert_includes message.errors[:attachments], "malware.exe has an unsupported file type"
  end

  test "an attachment filename with more than one period is rejected" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      attachments: [ { name: "image.001.jpeg", content_type: "image/jpeg", content: Base64.strict_encode64("x") } ])

    assert_not message.persisted?
    assert_includes message.errors[:attachments], "image.001.jpeg must not contain more than one period"
  end

  test "an attachment missing content is rejected" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello",
      attachments: [ { name: "test.txt", content_type: "text/plain", content: "" } ])

    assert_not message.persisted?
    assert_includes message.errors[:attachments], "test.txt is missing content"
  end

  test "an inline image (html only) gets a matching Content-ID and inline disposition" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi",
      html: "<p>see <img src=\"cid:logo.cid\"></p>",
      attachments: [ { name: "logo.png", content_type: "image/png", content: Base64.strict_encode64("pngbytes"), cid: "<logo.cid>" } ])

    assert message.persisted?
    parsed = Mail.new(message.raw)
    image = parsed.attachments.find { |a| a.filename == "logo.png" }
    assert_equal "<logo.cid>", image.content_id
    assert_match(/inline/, image.content_disposition)
    assert_equal "pngbytes", image.body.decoded
  end

  test "raw is stored as an attached rfc822 blob and round-trips the exact bytes" do
    raw = "Subject: hi\r\n\r\nhello"
    message = Message.create!(domain: domains(:example), mail_from: "a@example.com", raw: raw)

    assert message.raw_email.attached?
    assert_equal "message/rfc822", message.raw_email.content_type
    assert_equal raw, Message.find(message.id).raw
  end

  test "subject is persisted when raw is assigned" do
    message = Message.create!(domain: domains(:example), mail_from: "a@example.com", raw: "Subject: hi\r\n\r\nhello world")

    assert_equal "hi", message[:subject]
    assert_equal "hi", Message.find(message.id).subject
  end

  test "a mail without a subject persists an empty string so it is never reparsed" do
    message = Message.create!(domain: domains(:example), mail_from: "a@example.com", raw: "From: a@example.com\r\n\r\nno subject here")

    assert_equal "", message[:subject]
    assert_equal "", Message.find(message.id).subject
  end

  test "messages carry a created_at index for the retention purge" do
    columns = Message.connection.indexes(:messages).map(&:columns)

    assert_includes columns, %w[ created_at ]
  end

  test "incinerate_all_due strips the raw email attachment and blob but keeps the message" do
    message = Message.create!(domain: domains(:example), mail_from: "a@example.com", raw: "Subject: old\r\n\r\nbody")
    message.update_column(:created_at, 31.days.ago)

    assert_difference -> { ActiveStorage::Attachment.count } => -1, -> { ActiveStorage::Blob.count } => -1 do
      Message.incinerate_all_due
    end

    assert Message.exists?(message.id)
    assert message.reload.incinerated?
    assert_not message.raw_email.attached?
  end

  test "incinerate_all_due keeps the raw of an old message with an in-flight delivery" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello")
    message.update_column(:created_at, 31.days.ago)

    assert_no_difference -> { ActiveStorage::Blob.count } do
      Message.incinerate_all_due
    end

    assert_not message.reload.incinerated?
    assert message.raw_email.attached?
  end

  test "incinerate_all_due incinerates an old message once every delivery is terminal, keeping the deliveries" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], text: "hello")
    message.deliveries.update_all(status: :delivered)
    message.update_column(:created_at, 31.days.ago)

    assert_difference -> { ActiveStorage::Blob.count } => -1 do
      Message.incinerate_all_due
    end

    assert message.reload.incinerated?
    assert_not message.raw_email.attached?
    assert message.deliveries.any?, "delivery history is kept"
  end

  test "an inline image alongside a real attachment keeps them structurally distinct" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi",
      text: "hello", html: "<p>see <img src=\"cid:logo.cid\"></p>",
      attachments: [
        { name: "logo.png", content_type: "image/png", content: Base64.strict_encode64("pngbytes"), cid: "<logo.cid>" },
        { name: "invoice.pdf", content_type: "application/pdf", content: Base64.strict_encode64("pdfbytes") }
      ])

    assert message.persisted?
    parsed = Mail.new(message.raw)
    image = parsed.attachments.find { |a| a.filename == "logo.png" }
    pdf = parsed.attachments.find { |a| a.filename == "invoice.pdf" }

    assert_match(/inline/, image.content_disposition)
    assert_equal "<logo.cid>", image.content_id
    assert_match(/attachment/, pdf.content_disposition)
    assert_equal "pdfbytes", pdf.body.decoded
    assert_includes message.raw, "multipart/alternative"
  end

  test "submit stores the composed Message-ID" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "hello")

    assert message.persisted?
    assert_equal Mail.new(message.raw).message_id, message.mail_message_id.delete_prefix("<").delete_suffix(">")
    assert_match(/\A<.+@example\.com>\z/, message.mail_message_id)
  end

  test "submit splits comma-separated recipients into one delivery each" do
    message = Message.submit(domain: domains(:example), from: "a@example.com",
      to: "b@example.com, Cee <c@example.com>", subject: "hi", text: "hello")

    assert message.persisted?
    assert_equal %w[ b@example.com c@example.com ], message.deliveries.pluck(:rcpt_to).sort
    assert_includes message.raw.gsub(/\r\n /, " "), "Cee <c@example.com>"
  end

  test "submit stores metadata and echoes it in the delivery webhook payload" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", text: "hello", metadata: { "order_id" => "1234" })

    assert message.persisted?
    payload = message.deliveries.first.webhook_payload("delivery_delivered")
    assert_equal({ "order_id" => "1234" }, message.metadata)
    assert_equal({ "order_id" => "1234" }, payload[:metadata])
    assert_equal message.mail_message_id, payload[:message_id]
  end

  test "submit coerces metadata keys and values to strings" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", text: "hello", metadata: { order_id: 1234 })

    assert_equal({ "order_id" => "1234" }, message.metadata)
  end

  test "submit rejects metadata with too many entries" do
    entries = (1..Message::MAX_METADATA + 1).to_h { |n| [ "k#{n}", "v" ] }
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", text: "hello", metadata: entries)

    assert_not message.persisted?
    assert_includes message.errors[:metadata], "accepts at most #{Message::MAX_METADATA} entries"
  end

  test "submit rejects a non-object metadata value" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", text: "hello", metadata: "nope")

    assert_not message.persisted?
    assert_includes message.errors[:metadata], "must be an object"
  end

  test "submit rejects metadata values that are too long" do
    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", text: "hello",
      metadata: { "note" => "x" * (Message::MAX_METADATA_VALUE_LENGTH + 1) })

    assert_not message.persisted?
    assert_includes message.errors[:metadata], "values must be #{Message::MAX_METADATA_VALUE_LENGTH} characters or fewer"
  end

  test "a domain that hasn't published its DKIM record cannot originate mail" do
    message = Message.submit(domain: domains(:unverified), from: "a@unverified.example", to: [ "b@example.com" ],
      subject: "hi", text: "hello")

    assert_not message.persisted?
    assert_includes message.errors[:domain], "isn't verified for sending — publish its DKIM record, then check DNS"
  end

  # A forward travels under the relay's seal, so it never needs the tenant's key.
  test "a forward from that same domain is not held to it" do
    message = Message.submit_raw(domain: domains(:unverified), mail_from: "jane@remote.example",
      raw: "Subject: Hi\r\n\r\nBody", tags: [], recipients: [ "dest@elsewhere.example" ], origin: :forwarded)

    assert message.persisted?
  end

  # The tag is a label the sender writes; only the forwarding path may say what a
  # message is, or an API caller could exempt themselves from the rules above.
  test "tagging a submission forwarded does not make it one" do
    message = Message.submit(domain: domains(:unverified), from: "a@unverified.example", to: [ "b@example.com" ],
      subject: "hi", text: "hello", tags: [ "forwarded" ])

    assert_not message.persisted?
    assert message.submitted?
    assert_includes message.errors[:domain], "isn't verified for sending — publish its DKIM record, then check DNS"
  end

  test "a message containing a blocked phrase is stored, and none of its deliveries is sent" do
    domains(:example).update!(blocked_phrases: "free money")
    message = nil

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com", "c@example.com" ],
        subject: "hi", text: "Free, MONEY inside")
    end

    assert message.raw_email.attached?
    assert message.deliveries.all?(&:withheld?)
  end

  test "a raw submission containing a blocked phrase is withheld too" do
    domains(:example).update!(blocked_phrases: "free money")
    message = nil

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      message = Message.submit_raw(domain: domains(:example), mail_from: "a@example.com",
        raw: "Subject: Hi\r\n\r\nFree money inside", tags: [], recipients: [ "b@example.com" ])
    end

    assert message.deliveries.sole.withheld?
  end

  test "a withheld delivery records the phrase it was withheld for" do
    domains(:example).update!(blocked_phrases: "free money")

    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "Free money")

    event = message.deliveries.sole.events.sole
    assert_equal "delivery_withheld", event.action
    assert_equal "free money", event.particulars["phrase"]
  end

  test "a blocked phrase is found in the subject" do
    domains(:example).update!(blocked_phrases: "free money")

    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "Free money!", text: "hello")

    assert message.deliveries.sole.withheld?
  end

  test "a blocked phrase is found in html with its tags removed" do
    domains(:example).update!(blocked_phrases: "El empleado con Identificador")

    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", html: "<p>El empleado con <b>Identificador</b></p>")

    assert message.deliveries.sole.withheld?
  end

  test "a message that is itself a text file is not read as a body" do
    domains(:example).update!(blocked_phrases: "free money")

    message = Message.submit_raw(domain: domains(:example), mail_from: "a@example.com", tags: [], recipients: [ "b@example.com" ],
      raw: "Subject: Hi\r\nContent-Type: text/plain\r\nContent-Disposition: attachment; filename=notes.txt\r\n\r\nFree money")

    assert message.deliveries.sole.queued?
  end

  test "a forward is never checked for blocked phrases" do
    domains(:example).update!(blocked_phrases: "free money")

    message = Message.submit_raw(domain: domains(:example), mail_from: "jane@remote.example",
      raw: "Subject: Hi\r\n\r\nFree money inside", tags: [], recipients: [ "dest@elsewhere.example" ], origin: :forwarded)

    assert message.deliveries.sole.queued?
  end

  test "a domain with no blocked phrases never parses the message for them" do
    Message.any_instance.expects(:parsed_email).never

    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", html: "<p>hello</p>")

    assert message.deliveries.sole.queued?
  end

  test "html that cannot be read still leaves the subject and the text checked" do
    domains(:example).update!(blocked_phrases: "free money")
    ParsedEmail.any_instance.stubs(:html_text).raises(ArgumentError, "Document tree depth limit exceeded")
    Rails.error.expects(:report).with(instance_of(ArgumentError), severity: :warning)

    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ],
      subject: "hi", text: "Free money", html: "<p>hello</p>")

    assert message.deliveries.sole.withheld?
  end

  test "a check that breaks is reported and the message is sent" do
    domains(:example).update!(blocked_phrases: "free money")
    Domain.any_instance.stubs(:blocked_phrase_in).raises(RuntimeError)
    Rails.error.expects(:report).with(instance_of(RuntimeError), severity: :warning)

    message = Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "Free money")

    assert message.deliveries.sole.queued?
  end

  test "a withheld message reaches no webhook, not even one subscribed to failures" do
    domains(:example).update!(blocked_phrases: "free money")
    webhooks(:active).update!(subscribed_actions: Webhook::PERMITTED_ACTIONS)

    assert_not_includes Webhook::PERMITTED_ACTIONS, "delivery_withheld"
    assert_no_difference -> { Webhook::Delivery.count } do
      perform_enqueued_jobs only: Event::WebhookDispatchJob do
        Message.submit(domain: domains(:example), from: "a@example.com", to: [ "b@example.com" ], subject: "hi", text: "Free money")
      end
    end
  end
end
