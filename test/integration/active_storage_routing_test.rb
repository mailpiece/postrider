require "test_helper"

class ActiveStorageRoutingTest < ActionDispatch::IntegrationTest
  test "direct uploads reject anonymous clients so the blob store isn't a public dumping ground" do
    post rails_direct_uploads_path,
      params: { blob: { filename: "x.txt", byte_size: 3, checksum: "0" * 24, content_type: "text/plain" } },
      as: :json

    assert_response :redirect
    assert_equal 0, ActiveStorage::Blob.where(filename: "x.txt").count
  end

  test "an authenticated user can still direct-upload a blob" do
    sign_in_as :nonstaff

    post rails_direct_uploads_path,
      params: { blob: { filename: "x.txt", byte_size: 3, checksum: "0" * 24, content_type: "text/plain" } },
      as: :json

    assert_response :success
  end

  test "an account-prefixed blob URL round-trips because the middleware strips the numeric prefix" do
    sign_in_as :nonstaff

    blob = attachment_blob

    get rails_blob_path(blob, disposition: "attachment")

    assert_match %r{\A/#{Current.account.external_account_id}/rails/active_storage/}, request.fullpath
    assert_response :redirect

    follow_redirect!

    assert_response :success
    assert_equal "jpeg bytes", response.body
  end

  private
    def attachment_blob
      create_inbound_email(raw: raw_with_attachment)
        .tap(&:extract_attachments)
        .attachments_blobs.sole
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
