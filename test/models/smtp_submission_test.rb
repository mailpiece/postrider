require "test_helper"

class SmtpSubmissionTest < ActiveSupport::TestCase
  test "is valid when From and To are both present" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nSubject: Hi\r\n\r\nBody")

    assert submission.valid?
  end

  test "is invalid when a second From header would let an authorized address cover an unauthorized one" do
    submission = SmtpSubmission.new("From: a@example.com\r\nFrom: ceo@victim.example\r\nTo: b@example.com\r\n\r\nBody")

    assert_not submission.valid?
  end

  test "is invalid when one From header carries a second mailbox" do
    submission = SmtpSubmission.new("From: a@example.com, ceo@victim.example\r\nTo: b@example.com\r\n\r\nBody")

    assert_not submission.valid?
  end

  test "is valid when a single From mailbox has a display name containing a comma" do
    submission = SmtpSubmission.new("From: \"Doe, John\" <a@example.com>\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
  end

  test "is invalid when From is missing" do
    submission = SmtpSubmission.new("To: b@example.com\r\nSubject: Hi\r\n\r\nBody")

    assert_not submission.valid?
  end

  test "is invalid when To is missing" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSubject: Hi\r\n\r\nBody")

    assert_not submission.valid?
  end

  test "is valid when no identity header beyond From is present" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
    assert_equal [ "a@example.com" ], submission.identities
  end

  test "reports From and Sender as the identities to authorize" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSender: s@example.com\r\n" \
      "To: b@example.com\r\n\r\nBody")

    assert submission.valid?
    assert_equal [ "a@example.com", "s@example.com" ], submission.identities
  end

  test "is invalid when a second Sender header would cover an unauthorized address" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSender: a@example.com\r\nSender: ceo@victim.example\r\nTo: b@example.com\r\n\r\nBody")

    assert_not submission.valid?
  end

  test "is invalid when one Sender header carries a second mailbox" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSender: a@example.com, ceo@victim.example\r\nTo: b@example.com\r\n\r\nBody")

    assert_not submission.valid?
  end

  # RFC 5322 allows stacked resent blocks; we neither sign nor authorize them.
  test "is valid when a resent chain carries repeated Resent-From records" do
    submission = SmtpSubmission.new("Resent-From: carol@example.net\r\nResent-To: dave@example.org\r\n" \
      "Resent-From: bob@example.com\r\nResent-To: carol@example.net\r\n" \
      "From: a@example.com\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
    assert_equal [ "a@example.com" ], submission.identities
    assert_includes submission.raw, "Resent-From: bob@example.com"
  end

  test "is valid when a single Sender mailbox has a display name containing a comma" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSender: \"Doe, John\" <s@example.com>\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
    assert_equal [ "a@example.com", "s@example.com" ], submission.identities
  end

  test "reads a folded Sender header as the single address it names" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSender: \"Doe, John\"\r\n <s@example.com>\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
    assert_equal [ "a@example.com", "s@example.com" ], submission.identities
  end

  test "is invalid when a folded Sender header hides a second mailbox on its continuation line" do
    submission = SmtpSubmission.new("From: a@example.com\r\nSender: a@example.com,\r\n ceo@victim.example\r\nTo: b@example.com\r\n\r\nBody")

    assert_not submission.valid?
  end

  test "leaves Reply-To alone, since it legitimately names an address the sender doesn't own" do
    submission = SmtpSubmission.new("From: a@example.com\r\nReply-To: help@unrelated.example, sales@unrelated.example\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
    assert_equal [ "a@example.com" ], submission.identities
    assert_match "Reply-To: help@unrelated.example, sales@unrelated.example", submission.raw
  end

  test "strips a client-supplied Authentication-Results header" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "Authentication-Results: mx.example; dkim=pass header.d=victim.example\r\nSubject: Hi\r\n\r\nBody")

    assert_no_match(/authentication-results/i, submission.raw)
    assert_match "Subject: Hi", submission.raw
  end

  test "strips a client-supplied Received-SPF header, folded continuation and all" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "Received-SPF: pass (example.com: domain of a@example.com)\r\n client-ip=10.0.0.1\r\nSubject: Hi\r\n\r\nBody")

    assert_no_match(/received-spf/i, submission.raw)
    assert_no_match(/client-ip/, submission.raw)
    assert_match "Subject: Hi", submission.raw
  end

  test "strips client-supplied ARC headers" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "ARC-Seal: i=1; a=rsa-sha256; d=evil.example\r\n" \
      "ARC-Message-Signature: i=1; a=rsa-sha256; d=evil.example\r\n" \
      "ARC-Authentication-Results: i=1; mx.example\r\nSubject: Hi\r\n\r\nBody")

    assert_no_match(/arc-seal/i, submission.raw)
    assert_no_match(/arc-message-signature/i, submission.raw)
    assert_no_match(/arc-authentication-results/i, submission.raw)
    assert_match "Subject: Hi", submission.raw
  end

  test "strips a client-supplied Received header" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "Received: from trusted.example by mx.google.com; Mon, 1 Jan 2024 00:00:00 +0000\r\nSubject: Hi\r\n\r\nBody")

    assert_no_match(/^Received:/i, submission.raw)
    assert_match "Subject: Hi", submission.raw
  end

  test "extracts a comma-separated X-PostRider-Tags header" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nX-PostRider-Tags: tag one, tag two\r\n\r\nBody")

    assert_equal [ "tag one", "tag two" ], submission.tags
  end

  test "extracts a single X-PostRider-Tags value" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nX-PostRider-Tags: solo\r\n\r\nBody")

    assert_equal [ "solo" ], submission.tags
  end

  test "returns no tags when the header is absent" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n\r\nBody")

    assert_equal [], submission.tags
  end

  test "strips the X-PostRider-Tags header from the rewritten raw" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nX-PostRider-Tags: tag\r\n\r\nBody")

    assert_no_match(/x-postrider-tags/i, submission.raw)
  end

  test "promotes X-List-Unsubscribe to List-Unsubscribe and adds List-Unsubscribe-Post for an https URI" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nX-List-Unsubscribe: <https://example.com/unsub>\r\n\r\nBody")

    assert_match "List-Unsubscribe: <https://example.com/unsub>", submission.raw
    assert_match "List-Unsubscribe-Post: List-Unsubscribe=One-Click", submission.raw
    assert_no_match(/x-list-unsubscribe/i, submission.raw)
  end

  test "does not add List-Unsubscribe-Post for a mailto-only X-List-Unsubscribe value" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nX-List-Unsubscribe: <mailto:list@example.com>\r\n\r\nBody")

    assert_match "List-Unsubscribe: <mailto:list@example.com>", submission.raw
    assert_no_match(/List-Unsubscribe-Post/, submission.raw)
  end

  test "does not add List-Unsubscribe-Post when https only appears inside another URI's query string" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "X-List-Unsubscribe: <mailto:u@x?body=see https://example.com>\r\n\r\nBody")

    assert_no_match(/List-Unsubscribe-Post/, submission.raw)
  end

  test "replaces a client-supplied List-Unsubscribe with the X-List-Unsubscribe directive instead of appending a second one" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "List-Unsubscribe: <mailto:real@example.com>\r\nX-List-Unsubscribe: <https://example.com/unsub>\r\n\r\nBody")

    assert_equal 1, submission.raw.scan(/^List-Unsubscribe:/i).size
    assert_match "List-Unsubscribe: <https://example.com/unsub>", submission.raw
  end

  test "leaves a client-supplied List-Unsubscribe alone when there is no directive to replace it" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "List-Unsubscribe: <mailto:real@example.com>\r\n\r\nBody")

    assert_equal 1, submission.raw.scan(/^List-Unsubscribe:/i).size
    assert_match "List-Unsubscribe: <mailto:real@example.com>", submission.raw
  end

  test "leaves headers untouched when there are no directives and the Message-ID is already aligned" do
    raw = "From: a@example.com\r\nTo: b@example.com\r\nMessage-ID: <keep@example.com>\r\nDate: Mon, 1 Jan 2024 00:00:00 +0000\r\nSubject: Hi\r\n\r\nBody"

    assert_equal raw, SmtpSubmission.new(raw).raw
  end

  test "leaves a folded header intact" do
    raw = "From: a@example.com\r\nTo: b@example.com\r\nMessage-ID: <keep@example.com>\r\nDate: Mon, 1 Jan 2024 00:00:00 +0000\r\nSubject: hello\r\n world\r\n\r\nBody"

    assert_equal raw, SmtpSubmission.new(raw).raw
  end

  test "never touches the body even when directive headers are rewritten" do
    body = "line one\r\n\r\nline two with a blank line above\r\n"
    raw = "From: a@example.com\r\nTo: b@example.com\r\nX-PostRider-Tags: t\r\nX-List-Unsubscribe: <https://example.com>\r\n\r\n#{body}"

    assert_equal body, SmtpSubmission.new(raw).raw.split("\r\n\r\n", 2).last
  end

  test "keeps a Message-ID already at the From domain" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nMessage-ID: <abc@example.com>\r\n\r\nBody")

    assert_match "Message-ID: <abc@example.com>", submission.raw
    assert_equal 1, submission.raw.scan(/message-id:/i).size
  end

  test "matches the From domain case-insensitively when deciding a Message-ID is aligned" do
    submission = SmtpSubmission.new("From: a@Example.COM\r\nTo: b@example.com\r\nMessage-ID: <abc@example.com>\r\n\r\nBody")

    assert_match "Message-ID: <abc@example.com>", submission.raw
    assert_equal 1, submission.raw.scan(/message-id:/i).size
  end

  # mail gem's default Message-ID leaks the machine hostname; replace foreign hosts.
  test "replaces a Message-ID whose host isn't the From domain" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nMessage-ID: <abc@app-1.internal.example.mail>\r\n\r\nBody")

    assert_no_match(/internal\.example/, submission.raw)
    assert_match(/Message-ID: <[^@>]+@example\.com>/, submission.raw)
    assert_equal 1, submission.raw.scan(/message-id:/i).size
  end

  test "replaces every Message-ID with a single generated one when the submission carries more than one" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n" \
      "Message-ID: <one@example.com>\r\nMessage-ID: <two@evil.example>\r\n\r\nBody")

    assert_no_match(/evil\.example/, submission.raw)
    assert_no_match(/one@example\.com/, submission.raw)
    assert_equal 1, submission.raw.scan(/message-id:/i).size
  end

  test "stamps a Message-ID at the From domain when the submission carries none" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nSubject: Hi\r\n\r\nBody")

    assert_match(/Message-ID: <[^@>]+@example\.com>/, submission.raw)
  end

  test "generates the same Message-ID across repeated raw calls" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n\r\nBody")

    assert_equal submission.raw, submission.raw
  end

  test "stamps a Date when the submission carries none" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nSubject: Hi\r\n\r\nBody")

    assert_match(/Date: \w{3}, \d{1,2} \w{3} \d{4} \d{2}:\d{2}:\d{2} [+-]\d{4}/, submission.raw)
  end

  test "leaves an existing Date untouched, however malformed" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nDate: not a date\r\n\r\nBody")

    assert_match "Date: not a date", submission.raw
    assert_equal 1, submission.raw.scan(/date:/i).size
  end

  test "does not stamp a second Date when the client's has non-standard spacing before the colon" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nDate : Mon, 1 Jan 2024 00:00:00 +0000\r\n\r\nBody")

    assert_equal 1, submission.raw.scan(/date\s*:/i).size
  end

  test "generates the same Date across repeated raw calls" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\n\r\nBody")

    assert_equal submission.raw, submission.raw
  end

  test "recognizes a header with non-standard spacing before the colon, matching the tolerance already given Date and Message-ID" do
    submission = SmtpSubmission.new("From : a@example.com\r\nTo: b@example.com\r\n\r\nBody")

    assert submission.valid?
  end

  test "strips X-PostRider-Tags even with non-standard spacing before the colon" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nX-PostRider-Tags : tag\r\n\r\nBody")

    assert_equal [ "tag" ], submission.tags
    assert_no_match(/x-postrider-tags/i, submission.raw)
  end

  test "strips a bare CR not followed by LF from a header value" do
    submission = SmtpSubmission.new("From: a@example.com\r\nTo: b@example.com\r\nSubject: weird\rvalue\r\n\r\nBody")

    assert_match "Subject: weirdvalue", submission.raw
    assert_no_match(/weird\rvalue/, submission.raw)
  end

  IDENTITY_CANDIDATES = %w[ from sender reply-to resent-from resent-sender x-original-from x-sender ]
  SIGNED_WITHOUT_AUTHORIZATION = %w[ reply-to ]

  test "every identity header we sign is one we authorize" do
    signed = IDENTITY_CANDIDATES & Delivery::DkimSigning::SIGNED_HEADERS

    assert_equal (SmtpSubmission::IDENTITY_HEADERS + SIGNED_WITHOUT_AUTHORIZATION).sort, signed.sort
  end
end
