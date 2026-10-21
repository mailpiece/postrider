require "test_helper"
require "base64"

class InboundEmail::PayloadTest < ActiveSupport::TestCase
  setup do
    @image_bytes = file_fixture("moon.jpg").binread
  end

  test "a bare message with no Content-Type still carries its text body" do
    email = InboundEmail.new(mail_from: "a@test.com", rcpt_to: "b@test.com",
      raw: "From: a@test.com\r\nSubject: Bare\r\n\r\nJust a plain body.\r\n")

    payload = email.webhook_payload("inbound_email_received")

    assert_equal "Just a plain body.", payload[:text].strip
    assert_nil payload[:html]
  end

  test "renders the full Mailpiece payload for a multipart email" do
    payload = build_email.webhook_payload("inbound_email_received")

    assert_equal "Person A <a@test.com>", payload[:from]
    assert_equal [ "Person B <b@test.com>" ], payload[:to]
    assert_equal [ "Person C <c@test.com>" ], payload[:cc]
    assert_equal "Hello there", payload[:subject]
    assert_equal "<msg-123@test.com>", payload[:message_id]
    assert_equal "<prev-456@test.com>", payload[:in_reply_to]

    assert_kind_of Array, payload[:headers]
    assert payload[:headers].any? { |line| line.start_with?("Subject: ") }

    assert_includes payload[:html], "the html body"
    assert_includes payload[:text], "the text body"
  end

  test "recipients are split into an array, keeping a comma inside a display name intact" do
    email = InboundEmail.new(mail_from: "a@test.com", rcpt_to: "alice@x.com",
      raw: %(To: "Smith, Alice" <alice@x.com>, bob@y.com\r\nSubject: hi\r\n\r\nbody))

    payload = email.webhook_payload("inbound_email_received")

    assert_equal [ %("Smith, Alice" <alice@x.com>), "bob@y.com" ], payload[:to]
  end

  test "never carries the RFC822 bytes, so a big attachment cannot inflate the payload" do
    mail = Mail.new do
      from    "a@test.com"
      to      "b@test.com"
      subject "Photos"

      text_part { body "see attached" }
    end
    mail.attachments["photo.bin"] = { mime_type: "application/octet-stream", content: Random.bytes(1.megabyte) }
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@test.com", rcpt_to: "b@test.com", raw: mail.to_s)
    email.extract_attachments

    payload = email.webhook_payload("inbound_email_received")

    assert_not payload.key?(:raw)
    assert_equal 1.megabyte, payload[:attachments].sole[:size]
    assert_operator payload.to_json.bytesize, :<, 16.kilobytes
  end

  test "renders the image attachment with metadata and size, without embedding content" do
    payload = build_email.webhook_payload("inbound_email_received")

    assert_equal 2, payload[:attachments].size
    photo = payload[:attachments].find { |a| a[:filename] == "photo.jpg" }

    assert_nil photo[:content]
    assert_not photo.key?(:content)
    assert photo[:checksum].present?
    assert_equal @image_bytes.bytesize, photo[:size]
    assert_equal "image/jpeg", photo[:contentType]
    assert_equal "attachment", photo[:type]
  end

  test "carries a download URL for each attachment instead of its bytes" do
    email = build_email
    payload = email.webhook_payload("inbound_email_received")
    photo = payload[:attachments].find { |a| a[:filename] == "photo.jpg" }

    assert_match %r{\Ahttps?://}, photo[:url]
    assert_match %r{/rails/active_storage/blobs/}, photo[:url]
    assert_not photo.key?(:content)
  end

  # URL is built in a job with no request script_name, so it must include the account slug.
  test "prefixes the attachment URL with the account slug" do
    email = build_email
    payload = email.webhook_payload("inbound_email_received")
    photo = payload[:attachments].find { |a| a[:filename] == "photo.jpg" }

    assert_match %r{\Ahttps?://[^/]+#{email.account.slug}/rails/active_storage/}, photo[:url]
  end

  test "flags an inline image as related with a cid" do
    payload = build_email.webhook_payload("inbound_email_received")

    inline = payload[:attachments].find { |a| a[:cid] == "inline-789@test.com" }

    assert inline[:related]
    assert_equal "<inline-789@test.com>", inline[:contentId]
    assert_equal "inline-789@test.com", inline[:cid]
  end

  test "surfaces persisted SPF, DKIM, and DMARC verdicts under authentication" do
    email = build_email
    email.spf = "pass"
    email.dkim = "fail"
    email.dmarc = "none"

    payload = email.webhook_payload("inbound_email_received")

    assert_equal({ spf: "pass", dkim: "fail", dmarc: "none", from_aligned: false }, payload[:authentication])
  end

  test "says what the domain asked to happen to a DMARC failure" do
    email = build_email
    email.dmarc = "fail"
    email.dmarc_policy = "reject"

    payload = email.webhook_payload("inbound_email_received")

    assert_equal({ dmarc: "fail", dmarc_policy: "reject", from_aligned: false }, payload[:authentication])
  end

  test "surfaces the ARC chain status under authentication, and who sealed it" do
    email = build_email
    email.dmarc = "fail"
    email.arc = "pass"
    email.arc_sealer = "lists.example.org"

    payload = email.webhook_payload("inbound_email_received")

    assert_equal({ dmarc: "fail", arc: "pass", arc_sealer: "lists.example.org", from_aligned: false },
      payload[:authentication])
  end

  test "names authentication_results as the API does, carrying the string a relay gets as its header" do
    email = build_email
    email.spf = "pass"
    email.authentication_results = "mx.test; spf=pass smtp.mailfrom=a@test.com; dkim=pass header.d=test.com"

    payload = email.webhook_payload("inbound_email_received")

    assert_equal "mx.test; spf=pass smtp.mailfrom=a@test.com; dkim=pass header.d=test.com",
      payload[:authentication][:authentication_results]
  end

  # false is blank, so a bare compact would drop it and leave "not aligned" reading as "not reported".
  test "states from_aligned either way once anything was recorded" do
    aligned = build_email
    aligned.dmarc = "pass"
    aligned.from_aligned = true

    unaligned = build_email
    unaligned.dmarc = "fail"

    assert_equal true, aligned.webhook_payload("inbound_email_received")[:authentication][:from_aligned]
    assert_equal false, unaligned.webhook_payload("inbound_email_received")[:authentication][:from_aligned]
  end

  test "omits authentication entirely when no verdict was recorded" do
    payload = build_email.webhook_payload("inbound_email_received")

    assert_not payload.key?(:authentication)
  end

  test "a malformed raw email still returns the envelope sender without raising" do
    email = InboundEmail.new(mail_from: "a@test.com", rcpt_to: "b@test.com", raw: "not a real email")

    payload = assert_nothing_raised { InboundEmail::Payload.new(email).to_h }

    assert_equal "a@test.com", payload[:from]
    assert_not payload.key?(:raw)
    assert_not payload.key?(:id)
  end

  test "a message nested too deep to parse still returns the envelope sender without raising" do
    email = InboundEmail.new(mail_from: "a@test.com", rcpt_to: "b@test.com", raw: deeply_nested_raw)

    payload = assert_nothing_raised { InboundEmail::Payload.new(email).to_h }

    assert_equal "a@test.com", payload[:from]
  end

  test "carries the parsed DMARC report for mail sent to the dmarc-reports address" do
    email = InboundEmail.create!(domain: domains(:example), mail_from: "noreply-dmarc-support@google.com",
      rcpt_to: "dmarc-reports@example.com", raw: dmarc_report_raw).tap(&:extract_attachments)

    payload = email.webhook_payload("inbound_email_received")

    report = payload[:dmarc_report]
    assert_equal "google.com", report[:organization]
    assert_equal "test.com", report[:policy][:domain]
    assert_equal 1, report[:records].size
    assert_equal "203.0.113.9", report[:records].first[:source_ip]
    assert_kind_of Time, report[:range][:begin]
  end

  test "omits dmarc_report entirely for ordinary mail" do
    payload = build_email.webhook_payload("inbound_email_received")

    assert_not payload.key?(:dmarc_report)
  end

  test "identifies which mailbox the message arrived at, and itself" do
    email = build_email

    payload = email.webhook_payload("inbound_email_received")

    assert_equal email.mailpiece.id, payload[:id]
    assert_equal "b@test.com", payload[:rcpt_to]
  end

  private
    def build_email
      mail = Mail.new do
        from    "Person A <a@test.com>"
        to      "Person B <b@test.com>"
        cc      "Person C <c@test.com>"
        subject "Hello there"
        message_id "<msg-123@test.com>"
        in_reply_to "<prev-456@test.com>"

        text_part { body "the text body" }
        html_part do
          content_type "text/html; charset=UTF-8"
          body "<p>the html body</p>"
        end
      end

      mail.attachments["photo.jpg"] = { mime_type: "image/jpeg", content: @image_bytes }
      mail.attachments.inline["logo.jpg"] = { mime_type: "image/jpeg", content: @image_bytes }
      mail.attachments["logo.jpg"].content_id = "<inline-789@test.com>"

      InboundEmail.create!(domain: domains(:example), mail_from: "a@test.com", rcpt_to: "b@test.com", raw: mail.to_s).tap(&:extract_attachments)
    end

    def dmarc_report_raw
      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8" ?>
        <feedback>
          <report_metadata>
            <org_name>google.com</org_name>
            <report_id>14054835605949254452</report_id>
            <date_range><begin>1785196800</begin><end>1785283199</end></date_range>
          </report_metadata>
          <policy_published>
            <domain>test.com</domain>
            <p>reject</p>
          </policy_published>
          <record>
            <row>
              <source_ip>203.0.113.9</source_ip>
              <count>42</count>
              <policy_evaluated>
                <disposition>none</disposition>
                <dkim>pass</dkim>
                <spf>pass</spf>
              </policy_evaluated>
            </row>
            <identifiers><header_from>test.com</header_from></identifiers>
          </record>
        </feedback>
      XML

      <<~EOM
        From: noreply-dmarc-support@google.com
        To: dmarc-reports@test.com
        Subject: Report domain: test.com
        Content-Type: multipart/mixed; boundary=MIX

        --MIX
        Content-Type: text/plain

        see attached
        --MIX
        Content-Type: application/xml; name="aggregate.xml"
        Content-Disposition: attachment; filename="aggregate.xml"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64(xml)}
        --MIX--
      EOM
    end
end
