require "test_helper"

class ParsedEmailTest < ActiveSupport::TestCase
  test "exposes subject and a plain text_body for a multipart message" do
    mail = Mail.new do
      from    "Person A <a@test.com>"
      to      "Person B <b@test.com>"
      subject "Hello there"

      text_part { body "the text body" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<style>/* Email styles need to be inline */</style><p>the html body</p><script>alert(1)</script>"
      end
    end

    parsed = ParsedEmail.new(mail.to_s)

    assert parsed.present?
    assert_equal "Hello there", parsed.subject
    assert_equal "the text body", parsed.text_body.strip
    assert_not parsed.html_only?
  end

  test "html_only is true only of mail whose body is html alone" do
    assert ParsedEmail.new("Content-Type: text/html\r\nSubject: Hi\r\n\r\n<p>body</p>").html_only?
    assert ParsedEmail.new(with_related_image).html_only?
    assert_not ParsedEmail.new("Subject: Hi\r\n\r\nBody").html_only?
    assert_not ParsedEmail.new("Content-Type: application/zip\r\n\r\nzip").html_only?
    assert_not ParsedEmail.new(nil).html_only?
  end

  test "html_alternative is true only of mail carrying an html part beside its text" do
    mail = Mail.new do
      text_part { body "the text body" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>the html body</p>"
      end
    end

    assert ParsedEmail.new(mail.to_s).html_alternative?
    assert_not ParsedEmail.new("Subject: Hi\r\n\r\nBody").html_alternative?
    assert_not ParsedEmail.new("Content-Type: text/html\r\nSubject: Hi\r\n\r\n<p>body</p>").html_alternative?
    assert_not ParsedEmail.new(with_related_image).html_alternative?
    assert_not ParsedEmail.new(nil).html_alternative?
    assert_not ParsedEmail.new("not a real email").html_alternative?
  end

  test "html_text reads the html part as it renders, keeping words in tags a sanitizer would drop" do
    parsed = ParsedEmail.new("Content-Type: text/html; charset=UTF-8\r\n\r\n" \
      "<p>Tom &amp; <b>Jerry</b></p><p>next <o:p>door</o:p></p><script>alert(1)</script><style>p { color: red }</style>")

    assert_equal "Tom & Jerry next door", parsed.html_text.squish
  end

  test "html_text is nothing for mail without an html part" do
    assert_nil ParsedEmail.new("Subject: Hi\r\n\r\nBody").html_text
  end

  test "a single part sent as a file is a bare attachment, and a body is not" do
    assert ParsedEmail.new("Content-Type: text/plain\r\nContent-Disposition: attachment; filename=notes.txt\r\n\r\nBody").bare_attachment?
    assert_not ParsedEmail.new("Subject: Hi\r\n\r\nBody").bare_attachment?
  end

  test "an html-only mail has no text body" do
    mail = Mail.new do
      from    "a@test.com"
      to      "b@test.com"
      subject "HTML only"
      content_type "text/html; charset=UTF-8"
      body "<style>/* Email styles need to be inline */</style><p>the html body</p>"
    end

    parsed = ParsedEmail.new(mail.to_s)

    assert_nil parsed.text_body
  end

  test "a bare message with no Content-Type still carries its text body" do
    parsed = ParsedEmail.new("From: a@test.com\r\nSubject: Bare\r\n\r\nJust a plain body.\r\n")

    assert_equal "Just a plain body.", parsed.text_body.strip
  end

  test "source returns the original raw message, scrubbed for display" do
    parsed = ParsedEmail.new("From: a@test.com\r\nSubject: Bare\r\n\r\nJust a plain body.\r\n")

    assert_includes parsed.source, "Subject: Bare"
  end

  test "a garbage raw string does not raise and yields blank fields" do
    parsed = assert_nothing_raised { ParsedEmail.new("not a real email") }

    assert parsed.present?
    assert_nil parsed.subject
  end

  test "an unparseable message yields no stored attachments" do
    assert_empty ParsedEmail.new("not a real email").stored_attachments
  end

  test "a message nested too deep to parse is treated as unparseable" do
    parsed = assert_nothing_raised { ParsedEmail.new(deeply_nested_raw) }

    assert_not parsed.present?
    assert_nil parsed.text_body
    assert_empty parsed.stored_attachments
  end

  test "enumerates every attachment part, inline images included, for extraction" do
    raw = <<~EOM
      From: a@test.com
      To: b@test.com
      Subject: Mixed
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

    attachment = ParsedEmail.new(raw).stored_attachments.sole

    assert_equal "photo.jpg", attachment.filename
    assert_equal "image/jpeg", attachment.content_type
    assert_equal "jpeg bytes", attachment.bytes
    assert_not attachment.inline?
  end

  test "keeps a Gmail attachment that carries a Content-ID but is never referenced in the body as a listed attachment" do
    attachments = ParsedEmail.new(gmail_with_eight_attachments).stored_attachments

    assert_equal 8, attachments.size
    assert attachments.all? { |attachment| attachment.cid.present? }
    assert attachments.none?(&:inline?)
  end

  test "extracts a single-part message that is itself the attachment, as Google mails a DMARC report" do
    attachment = ParsedEmail.new(google_dmarc_report).stored_attachments.sole

    assert_equal "google.com!postrider.dev!1785196800!1785283199.zip", attachment.filename
    assert_equal "application/zip", attachment.content_type
    assert_equal "the report zip", attachment.bytes
    assert_not attachment.inline?
  end

  test "a single-part report dispositioned inline but carrying no cid is still a listed attachment" do
    attachment = ParsedEmail.new(fastmail_dmarc_report).stored_attachments.sole

    assert_equal "fastmail.com!postrider.dev!1785196800!1785283199.xml.gz", attachment.filename
    assert_equal "the report gzip", attachment.bytes
    assert_not attachment.inline?
  end

  test "treats a cid part as inline only when the html body references it, regardless of its disposition" do
    raw = <<~EOM
      From: a@test.com
      To: b@test.com
      Subject: Referenced
      Content-Type: multipart/related; boundary=BND

      --BND
      Content-Type: text/html; charset=UTF-8

      <p><img src="cid:pic@test"></p>
      --BND
      Content-Type: image/png; name="pic.png"
      Content-Disposition: attachment; filename="pic.png"
      Content-ID: <pic@test>
      Content-Transfer-Encoding: base64

      #{Base64.strict_encode64("png bytes")}
      --BND--
    EOM

    assert ParsedEmail.new(raw).stored_attachments.sole.inline?
  end

  test "exposes the From address and display name" do
    parsed = ParsedEmail.new("From: Jane Doe <jane@remote.example>\r\nSubject: Hi\r\n\r\nBody")

    assert_equal "jane@remote.example", parsed.from_address
    assert_equal "Jane Doe", parsed.from_name
  end

  test "a bare From address carries no display name" do
    parsed = ParsedEmail.new("From: jane@remote.example\r\nSubject: Hi\r\n\r\nBody")

    assert_equal "jane@remote.example", parsed.from_address
    assert_nil parsed.from_name
  end

  test "a malformed or missing From line yields no sender instead of raising" do
    assert_nil ParsedEmail.new("From: <<<>>>\r\nSubject: Hi\r\n\r\nBody").from_address
    assert_nil ParsedEmail.new("Subject: Hi\r\n\r\nBody").from_address
    assert_nil ParsedEmail.new(nil).from_address
  end

  private
    def google_dmarc_report
      <<~EOM
        From: noreply-dmarc-support@google.com
        To: dmarc-reports@postrider.dev
        Subject: Report domain: postrider.dev Submitter: google.com Report-ID: 15696909972292815132
        MIME-Version: 1.0
        Content-Type: application/zip;
            name="google.com!postrider.dev!1785196800!1785283199.zip"
        Content-Disposition: attachment;
            filename="google.com!postrider.dev!1785196800!1785283199.zip"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64("the report zip")}
      EOM
    end

    def fastmail_dmarc_report
      <<~EOM
        From: dmarc-reports@fastmail.com
        To: dmarc-reports@postrider.dev
        Subject: Report domain: postrider.dev Submitter: fastmail.com
        Content-Type: application/gzip
        Content-Disposition: inline; filename="fastmail.com!postrider.dev!1785196800!1785283199.xml.gz"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64("the report gzip")}
      EOM
    end

    GMAIL_ATTACHMENTS = [
      [ "animation.gif", "image/gif",  "f_gif0001" ],
      [ "avatar.png",    "image/png",  "f_png0002" ],
      [ "photo-1.jpg",   "image/jpeg", "f_jpg0003" ],
      [ "photo-2.jpg",   "image/jpeg", "f_jpg0004" ],
      [ "photo-3.jpg",   "image/jpeg", "f_jpg0005" ],
      [ "photo-4.jpg",   "image/jpeg", "f_jpg0006" ],
      [ "photo-5.jpg",   "image/jpeg", "f_jpg0007" ],
      [ "photo-6.jpg",   "image/jpeg", "f_jpg0008" ]
    ].freeze

    def gmail_with_eight_attachments
      parts = GMAIL_ATTACHMENTS.map do |filename, type, cid|
        <<~PART
          --MIX
          Content-Type: #{type}; name="#{filename}"
          Content-Disposition: attachment; filename="#{filename}"
          Content-Transfer-Encoding: base64
          X-Attachment-Id: #{cid}
          Content-ID: <#{cid}>

          #{Base64.strict_encode64("bytes for #{filename}")}
        PART
      end.join

      <<~EOM
        From: Gmail User <user@gmail.com>
        To: jane@example.com
        Subject: Photos
        Content-Type: multipart/mixed; boundary=MIX

        --MIX
        Content-Type: multipart/alternative; boundary=ALT

        --ALT
        Content-Type: text/plain; charset="UTF-8"

        Jane.
        --ALT
        Content-Type: text/html; charset="UTF-8"

        <div dir="ltr">Jane.<div><br></div><div class="gmail_signature">Sent from Gmail</div></div>
        --ALT--
        #{parts}--MIX--
      EOM
    end

    def with_related_image
      <<~EOM
        From: a@test.com
        To: b@test.com
        Subject: Inline image
        Content-Type: multipart/related; boundary=BND

        --BND
        Content-Type: text/html; charset=UTF-8

        <p>see <img src="cid:logo@test"></p>
        --BND
        Content-Type: image/png
        Content-ID: <logo@test>
        Content-Disposition: inline; filename=logo.png
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64("the image bytes")}
        --BND--
      EOM
    end
end
