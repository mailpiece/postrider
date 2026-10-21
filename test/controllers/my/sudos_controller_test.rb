require "test_helper"

class My::SudosControllerTest < ActionDispatch::IntegrationTest
  include WebauthnTestHelper

  setup do
    integration_session.default_url_options = integration_session.default_url_options.merge(host: "www.example.com")
    sign_in_as :leo
  end

  test "new" do
    create_passkey

    get new_my_sudo_path
    assert_response :success
  end

  test "new without a passkey sends you to add one" do
    get new_my_sudo_path
    assert_redirected_to my_passkeys_path
  end

  test "confirming with a passkey returns to the gated form" do
    # Asked before any URL helper runs: one called since the last request keeps the account prefix, even inside untenanted.
    challenge = request_webauthn_challenge

    get new_my_access_token_path
    assert_redirected_to new_my_sudo_path

    post my_sudo_path, params: build_assertion_params(challenge: challenge, credential: create_passkey)

    assert_redirected_to new_my_access_token_url
    follow_redirect!
    assert_response :success
  end

  test "another identity's passkey does not confirm" do
    challenge = request_webauthn_challenge

    post my_sudo_path, params: build_assertion_params(challenge: challenge, credential: create_passkey(identity: identities(:nonstaff)))

    assert_redirected_to new_my_sudo_path
    get new_my_access_token_path
    assert_redirected_to new_my_sudo_path
  end

  private
    def create_passkey(identity: identities(:leo))
      identity.passkeys.create!(credential_id: Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false),
        public_key: webauthn_private_key.public_to_der)
    end
end
