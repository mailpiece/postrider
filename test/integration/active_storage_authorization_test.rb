require "test_helper"

class ActiveStorageAuthorizationTest < ActionDispatch::IntegrationTest
  test "an authenticated user with domain access can download an attachment" do
    sign_in_as :leo

    get rails_blob_path(attachment_blob, disposition: "attachment")

    assert_response :redirect

    follow_redirect!

    assert_response :success
    assert_equal "jpeg bytes", response.body
  end

  test "a blob URL stripped of its account slug serves nothing, however good the session" do
    sign_in_as :leo

    get rails_blob_path(attachment_blob, disposition: "attachment", script_name: "")

    assert_response :redirect
    assert_match %r{/session/menu}, response.location
  end

  test "a bearer token with domain access can download an attachment" do
    get rails_blob_path(attachment_blob, disposition: "attachment"), env: api_token_env

    assert_response :redirect

    follow_redirect!

    assert_response :success
    assert_equal "jpeg bytes", response.body
  end

  test "an authenticated user without domain access cannot download an attachment" do
    sign_in_as :nonstaff
    blob = attachment_blob(domain: domains(:private))

    get rails_blob_path(blob, disposition: "attachment")

    assert_response :forbidden
  end

  test "an unauthenticated user is sent to the login page instead of the bytes" do
    get rails_blob_path(attachment_blob, disposition: "attachment")

    assert_response :redirect
    assert_match %r{/session/new}, response.location
  end

  test "an authenticated user cannot download an attachment from another account" do
    sign_in_as :leo
    blob = other_account_inbound_email.attachments_blobs.sole

    get rails_blob_path(blob, disposition: "attachment")

    assert_response :forbidden
  end

  test "an authenticated user with domain access can download the raw message" do
    sign_in_as :leo

    get rails_blob_path(raw_blob(inbound_emails(:received)), disposition: "attachment")

    assert_response :redirect

    follow_redirect!

    assert_response :success
    assert_equal file_fixture("raw.eml").read, response.body
  end

  test "an authenticated user without domain access cannot download the raw message" do
    sign_in_as :nonstaff
    inbound_email = create_inbound_email(domain: domains(:private))

    get rails_blob_path(inbound_email.raw_email.blob, disposition: "attachment")

    assert_response :forbidden
  end

  test "an unauthenticated user cannot download the raw message" do
    get rails_blob_path(raw_blob(inbound_emails(:received)), disposition: "attachment")

    assert_response :redirect
    assert_match %r{/session/new}, response.location
  end

  test "an authenticated user cannot download the raw message of another account" do
    sign_in_as :leo
    blob = raw_blob(inbound_emails(:other_account))

    get rails_blob_path(blob, disposition: "attachment")

    assert_response :forbidden
  end

  test "an unattached blob is not readable" do
    sign_in_as :leo
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("orphaned"), filename: "orphan.eml",
      content_type: "message/rfc822")

    get rails_blob_path(blob, disposition: "attachment")

    assert_response :forbidden
  end

  test "proxied bytes never get public cache headers" do
    sign_in_as :leo

    get rails_storage_proxy_path(attachment_blob)

    assert_response :success
    assert_not_includes response.headers["Cache-Control"], "public"
  end

  [ "text/html;charset=utf-8", "text/html,foo", "TEXT/HTML", "text/x-html", "text/vnd.turbo-stream.html",
    "application/xhtml+xml+xxe", "image/svg+xml", "application/xml", "text/xml", "text/htmlé" ].each do |declared_type|
    test "a blob declared #{declared_type} is served as octet-stream" do
      sign_in_as :leo

      get rails_storage_proxy_path(markup_blob(declared_type))

      assert_response :success
      assert_equal "application/octet-stream", response.media_type
      assert_match %r{attachment}, response.headers["Content-Disposition"]
    end
  end

  test "an unauthenticated request never runs the representation parser" do
    paths = representation_paths
    ActiveStorage::Blob.any_instance.expects(:representation).never

    paths.each do |path|
      get path

      assert_response :redirect
      assert_match %r{/session/new}, response.location
    end
  end

  test "a forbidden request never runs the representation parser" do
    sign_in_as :leo

    paths = representation_paths
    ActiveStorage::Blob.any_instance.expects(:representation).never

    paths.each do |path|
      get path

      assert_response :forbidden
    end
  end

  private
    def attachment_blob(domain: domains(:example))
      create_inbound_email(domain: domain, raw: raw_with_attachment)
        .tap(&:extract_attachments)
        .attachments_blobs.sole
    end

    def raw_blob(inbound_email)
      inbound_email.raw = file_fixture("raw.eml").read
      inbound_email.raw_email.blob
    end

    def markup_blob(content_type)
      attachment_blob.tap { |blob| blob.update!(content_type: content_type) }
    end

    def representation_paths
      blob = ActiveStorage::Blob.create_and_upload!(io: file_fixture("moon.jpg").open, filename: "moon.jpg", content_type: "image/jpeg")
      variant = blob.representation(resize_to_limit: [ 100, 100 ])

      [ rails_representation_path(variant), rails_storage_proxy_path(variant) ]
    end

    def other_account_inbound_email
      create_inbound_email(domain: domains(:other_account), rcpt_to: "b@other-account.test", raw: raw_with_attachment)
        .tap(&:extract_attachments)
    end

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
