require "test_helper"

class My::PasskeysControllerTest < ActionDispatch::IntegrationTest
  include WebauthnTestHelper

  setup do
    sign_in_as :leo
  end

  test "index" do
    get my_passkeys_path
    assert_response :success
  end

  test "index renders untenanted" do
    untenanted { get my_passkeys_path }
    assert_response :success
  end

  test "the first passkey is registered without sudo" do
    challenge = request_webauthn_challenge(purpose: "registration")

    assert_difference -> { identities(:leo).passkeys.count }, 1 do
      post my_passkeys_path, params: build_attestation_params(challenge: challenge)
    end

    passkey = identities(:leo).passkeys.order(created_at: :desc).first
    assert_redirected_to edit_my_passkey_path(passkey, created: true)
    assert_equal [ "internal" ], passkey.transports
  end

  test "malformed attestation is rejected with a redirect, not a 500" do
    challenge = request_webauthn_challenge(purpose: "registration")
    params = build_attestation_params(challenge: challenge)
    params[:passkey][:attestation_object] = "this-is-not-a-valid-attestation-object"

    assert_no_difference -> { identities(:leo).passkeys.count } do
      post my_passkeys_path, params: params
    end

    assert_redirected_to my_passkeys_path
    assert_equal "We couldn't register that passkey. Please try again.", flash[:alert]
  end

  test "re-registering an existing credential is rejected with a friendly message" do
    challenge = request_webauthn_challenge(purpose: "registration")
    credential_id = SecureRandom.random_bytes(32)

    post my_passkeys_path, params: build_attestation_params(challenge: challenge, credential_id: credential_id)
    assert_response :redirect
    confirm_sudo

    challenge = request_webauthn_challenge(purpose: "registration")
    assert_no_difference -> { ActionPack::Passkey.count } do
      post my_passkeys_path, params: build_attestation_params(challenge: challenge, credential_id: credential_id)
    end

    assert_redirected_to my_passkeys_path
    assert_equal "That passkey is already registered.", flash[:alert]
  end

  test "rename and remove" do
    confirm_sudo
    passkey = create_passkey
    create_passkey

    patch my_passkey_path(passkey), params: { passkey: { name: "iPhone" } }
    assert_redirected_to my_passkeys_path
    assert_equal "iPhone", passkey.reload.name

    assert_difference -> { identities(:leo).passkeys.count }, -1 do
      delete my_passkey_path(passkey)
    end
  end

  test "adding or removing a passkey needs sudo once one exists" do
    passkey = create_passkey

    get my_passkeys_path
    assert_redirected_to new_my_sudo_path

    post my_passkeys_path, params: build_attestation_params(challenge: request_webauthn_challenge(purpose: "registration"))
    assert_redirected_to new_my_sudo_path

    assert_no_difference -> { identities(:leo).passkeys.count } do
      delete my_passkey_path(passkey)
    end
    assert_redirected_to new_my_sudo_path
  end

  test "the last passkey cannot be removed" do
    confirm_sudo
    passkey = create_passkey

    get edit_my_passkey_path(passkey)
    assert_select "p", text: /This is your only passkey/

    assert_no_difference -> { identities(:leo).passkeys.count } do
      delete my_passkey_path(passkey)
    end
    assert_redirected_to edit_my_passkey_path(passkey)
  end

  test "another identity's passkey is out of reach" do
    passkey = create_passkey(identity: identities(:nonstaff))

    delete my_passkey_path(passkey)

    assert_response :not_found
    assert ActionPack::Passkey.exists?(passkey.id)
  end

  test "an API token cannot register or remove a passkey" do
    passkey = create_passkey
    cookies.delete("session_token")

    delete my_passkey_path(passkey), env: api_token_env, as: :json
    assert_response :unauthorized

    challenge = request_webauthn_challenge(purpose: "registration")
    post my_passkeys_path, params: build_attestation_params(challenge: challenge), env: api_token_env, as: :json
    assert_response :unauthorized

    assert_equal [ passkey ], identities(:leo).passkeys.to_a
  end

  private
    def create_passkey(identity: identities(:leo))
      identity.passkeys.create!(credential_id: Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false),
        public_key: webauthn_private_key.public_to_der)
    end
end
