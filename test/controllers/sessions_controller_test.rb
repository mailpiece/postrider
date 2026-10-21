require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include WebauthnTestHelper

  test "new offers only a passkey" do
    identities(:leo).passkeys.create!(credential_id: "leo-credential", public_key: webauthn_private_key.public_to_der)

    assert_no_difference -> { Identity::Transfer.count } do
      untenanted { get new_session_path }
    end

    assert_response :success
    assert_select "rails-passkey-sign-in-button"
    assert_select "input[type=email]", count: 0
    assert_select "a", text: /Sign in as/, count: 0
  end

  test "new in development signs in as anyone" do
    identities(:leo).passkeys.create!(credential_id: "leo-credential", public_key: webauthn_private_key.public_to_der)
    Rails.env.stubs(:development?).returns(true)

    untenanted { get new_session_path }

    assert_response :success
    assert_select "a[href^=?]", "/session/transfers/", text: "Sign in as #{identities(:leo).email_address}"
  end

  test "new sends an install with no passkey yet to signup" do
    untenanted do
      get new_session_path
      assert_redirected_to new_signup_path
    end
  end

  test "new stays on sign in once signups close" do
    with_multi_tenant_mode(false) do
      untenanted { get new_session_path }
    end

    assert_response :success
  end
end
