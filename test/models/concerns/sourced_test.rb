require "test_helper"

class SourcedTest < ActiveSupport::TestCase
  test "a source parses the message once, however many records store it" do
    raw = "Subject: Fanout\r\n\r\nBody."
    parsed = ParsedEmail.new(raw)
    ParsedEmail.expects(:new).once.returns(parsed)

    source = Sourced::Source.new(raw)
    emails = 3.times.map do |n|
      InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "r#{n}@example.com", source: source, digest: "fanout")
    end

    assert_equal [ "Fanout" ], emails.map { |email| email[:subject] }.uniq
  end

  test "a source uploads the message once and shares that blob with every record that stores it" do
    source = Sourced::Source.new("Subject: Fanout\r\n\r\nBody.")

    emails = assert_difference -> { ActiveStorage::Blob.count } => 1, -> { ActiveStorage::Attachment.count } => 3 do
      3.times.map do |n|
        InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "r#{n}@example.com", source: source, digest: "fanout")
      end
    end

    assert_equal 1, emails.map { |email| email.reload.raw_email.blob.id }.uniq.size
    assert_equal [ "Subject: Fanout\r\n\r\nBody." ], emails.map { |email| InboundEmail.find(email.id).raw }.uniq
  end

  test "destroying one record that shares a source's blob leaves the message readable for the rest" do
    source = Sourced::Source.new("Subject: Fanout\r\n\r\nBody.")
    emails = 3.times.map do |n|
      InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "r#{n}@example.com", source: source, digest: "fanout")
    end

    assert_no_difference -> { ActiveStorage::Blob.count } do
      perform_enqueued_jobs { emails.first.destroy! }
    end

    assert_equal [ "Subject: Fanout\r\n\r\nBody." ], emails.drop(1).map { |email| InboundEmail.find(email.id).raw }.uniq
  end

  test "the summary parse reads only the head of the message, not a huge attachment" do
    raw = "Subject: big\r\n\r\n" + ("x" * (Sourced::Source::PARSE_BYTES + 1.kilobyte))
    parsed = ParsedEmail.new(raw)
    ParsedEmail.expects(:new).with { |head| head.bytesize == Sourced::Source::PARSE_BYTES }.returns(parsed)

    assert_equal raw, Sourced::Source.new(raw).raw
  end

  test "storing a source does not extract attachments; that waits for the forwarding job" do
    source = Sourced::Source.new(raw_with_attachment)

    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", source: source, digest: "d")

    assert_not email.attachments.attached?
  end

  test "extract_attachments stores each part as a blob carrying its cid and inline flag" do
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: raw_with_inline_and_attachment)

    email.extract_attachments

    assert_equal 2, email.attachments.blobs.size
    photo = email.attachments.blobs.find { |blob| blob.filename.to_s == "photo.jpg" }
    logo = email.attachments.blobs.find { |blob| blob.filename.to_s == "logo.png" }

    assert_equal "image/jpeg", photo.content_type
    assert_not photo.metadata["inline"]
    assert_nil photo.metadata["cid"]

    assert logo.metadata["inline"]
    assert_equal "logo@test", logo.metadata["cid"]
  end

  test "extract_attachments stores an image without any image library opening it" do
    assert_empty ActiveStorage.analyzers
    assert_empty ActiveStorage.previewers

    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: raw_with_attachment)
    perform_enqueued_jobs { email.extract_attachments }

    blob = email.attachments.blobs.sole
    assert blob.analyzed?
    assert_nil blob.metadata["width"]
  end

  test "extract_attachments stores the true content type and lets Active Storage serve browser-executable types as an opaque download" do
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: raw_with_svg)

    email.extract_attachments

    blob = email.attachments.blobs.sole
    assert_equal "image/svg+xml", blob.content_type
    assert_equal "application/octet-stream", blob.content_type_for_serving
    assert_equal :attachment, blob.forced_disposition_for_serving
  end

  test "extract_attachments is bounded and logs what it drops past the cap" do
    parts = (Sourced::MAX_ATTACHMENTS + 3).times.map { |i| attachment_part("f#{i}.bin", "application/octet-stream", "b#{i}") }
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: with_mixed(parts))

    Rails.logger.expects(:warn).with(regexp_matches(/dropped 3/))
    email.extract_attachments

    assert_equal Sourced::MAX_ATTACHMENTS, email.attachments.blobs.size
  end

  test "extract_attachments is idempotent, so a retried job does not double-store" do
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: raw_with_attachment)
    email.extract_attachments

    assert_no_difference -> { ActiveStorage::Attachment.count } do
      email.extract_attachments
    end
  end

  test "incinerate_all_due destroys a delivered email's extracted attachment blobs and their files, keeping the row" do
    email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: raw_with_attachment)
    email.forward(ip: "203.0.113.1", helo: "sender.example")
    email.update!(forwarded_at: 31.days.ago)
    attachment_blob = email.attachments.blobs.sole

    assert_difference -> { ActiveStorage::Blob.count } => -2 do
      InboundEmail.incinerate_all_due
    end

    assert_not attachment_blob.service.exist?(attachment_blob.key)
    assert email.reload.incinerated?
    assert_not email.attachments.attached?
  end

  private
    def raw_with_attachment
      with_mixed([ attachment_part("photo.jpg", "image/jpeg", "jpeg bytes") ])
    end

    def raw_with_svg
      with_mixed([ attachment_part("x.svg", "image/svg+xml", "<svg onload=alert(1)>") ])
    end

    def raw_with_inline_and_attachment
      <<~EOM
        From: a@example.com
        To: b@example.com
        Subject: Inline and attachment
        Content-Type: multipart/related; boundary=BND

        --BND
        Content-Type: text/html; charset=UTF-8

        <p>see <img src="cid:logo@test"></p>
        --BND
        Content-Type: image/png
        Content-ID: <logo@test>
        Content-Disposition: inline; filename=logo.png
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64("png bytes")}
        --BND
        Content-Type: image/jpeg; name="photo.jpg"
        Content-Disposition: attachment; filename="photo.jpg"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64("jpeg bytes")}
        --BND--
      EOM
    end

    def with_mixed(parts)
      "From: a@example.com\nTo: b@example.com\nSubject: With attachments\n" \
      "Content-Type: multipart/mixed; boundary=MIX\n\n" \
      "--MIX\nContent-Type: text/plain\n\nsee attached\n" \
      "#{parts.join}--MIX--\n"
    end

    def attachment_part(filename, content_type, bytes)
      <<~PART
        --MIX
        Content-Type: #{content_type}; name="#{filename}"
        Content-Disposition: attachment; filename="#{filename}"
        Content-Transfer-Encoding: base64

        #{Base64.strict_encode64(bytes)}
      PART
    end
end
