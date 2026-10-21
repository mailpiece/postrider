require "test_helper"

class Sessions::PasskeyRegistrationsControllerTest < ActionDispatch::IntegrationTest
  include WebauthnTestHelper

  test "signing up creates a passkey, then asks for a name" do
    untenanted do
      post signup_path, params: { signup: { email_address: "newcomer@example.com" } }
      assert_redirected_to new_session_passkey_registration_url

      get new_session_passkey_registration_path
      assert_response :success

      assert_difference -> { Identity.find_by!(email_address: "newcomer@example.com").passkeys.count }, 1 do
        post session_passkey_registration_path, params: build_attestation_params(challenge: request_webauthn_challenge(purpose: "registration"))
      end

      assert_redirected_to new_signup_completion_url
      assert parsed_cookies.signed[:session_token]
    end
  end

  test "a signup abandoned before its passkey can be retried" do
    untenanted do
      post signup_path, params: { signup: { email_address: "newcomer@example.com" } }

      assert_no_difference -> { Identity.count } do
        post signup_path, params: { signup: { email_address: "newcomer@example.com" } }
      end

      assert_redirected_to new_session_passkey_registration_url
    end
  end

  test "signing up with an email that already has an account goes to sign in" do
    untenanted do
      post signup_path, params: { signup: { email_address: identities(:leo).email_address } }
      assert_redirected_to new_session_url
      assert_nil flash[:alert]

      get new_session_passkey_registration_path
      assert_redirected_to new_session_path
    end
  end

  test "joining adds the person to the account once the passkey is registered" do
    account = accounts(:davids_account)

    assert_no_difference -> { account.users.count } do
      post join_path(code: account_join_codes(:davids_account).code, script_name: account.slug), params: { email_address: "joiner@example.com" }
    end

    untenanted do
      assert_difference -> { account.users.count }, 1 do
        post session_passkey_registration_path, params: build_attestation_params(challenge: request_webauthn_challenge(purpose: "registration"))
      end
    end

    assert_redirected_to new_users_verification_url(script_name: account.slug)
  end

  test "an invitation used up before the passkey registers nothing" do
    account = accounts(:davids_account)
    join_code = account_join_codes(:davids_account)

    post join_path(code: join_code.code, script_name: account.slug), params: { email_address: "joiner@example.com" }
    join_code.update!(usage_count: join_code.usage_limit)

    untenanted do
      assert_no_difference -> { Identity.find_by!(email_address: "joiner@example.com").passkeys.count } do
        post session_passkey_registration_path, params: build_attestation_params(challenge: request_webauthn_challenge(purpose: "registration"))
      end
    end

    assert_response :gone
    assert_includes response.body, "This invitation link can no longer be used"
  end

  test "an invitation reset before the passkey is not found" do
    account = accounts(:davids_account)
    join_code = account_join_codes(:davids_account)

    post join_path(code: join_code.code, script_name: account.slug), params: { email_address: "joiner@example.com" }
    join_code.reset

    untenanted do
      get new_session_passkey_registration_path
    end

    assert_response :not_found
  end

  test "a pending registration ends once its identity has a passkey" do
    untenanted do
      post signup_path, params: { signup: { email_address: "newcomer@example.com" } }
      Identity.find_by!(email_address: "newcomer@example.com").passkeys.create!(credential_id: "newcomer-credential", public_key: webauthn_private_key.public_to_der)

      get new_session_passkey_registration_path
      assert_redirected_to new_session_path
    end
  end

  test "nothing to register without a pending signup or invitation" do
    untenanted do
      get new_session_passkey_registration_path

      assert_redirected_to new_session_path
    end
  end
end
