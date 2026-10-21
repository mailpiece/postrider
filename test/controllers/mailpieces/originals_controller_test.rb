require "test_helper"

class Mailpieces::OriginalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :nonstaff
  end

  test "streams the original of an inbound-backed mailpiece as inline text/plain" do
    raw = <<~EOM
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
    inbound_email = create_inbound_email(raw: raw)

    get mailpiece_original_path(inbound_email.mailpiece)

    assert_response :success
    assert_equal raw, response.body
    assert_match %r{text/plain}, response.headers["Content-Type"]
    assert_match "inline", response.headers["Content-Disposition"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "streams the original of a delivery-backed mailpiece as inline text/plain" do
    messages(:queued).raw = file_fixture("raw.eml").read

    get mailpiece_original_path(mailpieces(:queued))

    assert_response :success
    assert_equal file_fixture("raw.eml").read, response.body
    assert_match %r{text/plain}, response.headers["Content-Type"]
    assert_match "inline", response.headers["Content-Disposition"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "returns not found for an inbound-backed mailpiece with no raw attached" do
    inbound_emails(:received).raw = file_fixture("raw.eml").read
    inbound_emails(:received).incinerate

    get mailpiece_original_path(mailpieces(:received))

    assert_response :not_found
  end

  test "returns not found for a delivery-backed mailpiece with no raw attached" do
    messages(:delivered).raw = file_fixture("raw.eml").read
    messages(:delivered).incinerate

    get mailpiece_original_path(mailpieces(:delivered))

    assert_response :not_found
  end

  test "cannot view the original of a mailpiece on a domain you have no access to" do
    inbound_email = create_inbound_email(domain: domains(:private), rcpt_to: "b@private.example")

    get mailpiece_original_path(inbound_email.mailpiece)

    assert_response :not_found
  end

  test "cannot view the original of another account's mailpiece" do
    get mailpiece_original_path(mailpieces(:other_account))

    assert_response :not_found
  end
end
