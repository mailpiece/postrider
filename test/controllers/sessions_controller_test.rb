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

  test "destroy closes every remote connection for the signed-out identity and lets valid sessions reconnect" do
    leo = users(:leo)
    other_account_user = User.create!(identity: leo.identity, account: accounts(:other_account), role: :member, name: "Leo Elsewhere")

    sign_in_as :leo

    disconnected_users = []
    reconnect_flags = []
    remote_connections = Object.new
    remote_connections.define_singleton_method(:where) { |current_user:| disconnected_users << current_user; self }
    remote_connections.define_singleton_method(:disconnect) { |reconnect:| reconnect_flags << reconnect }
    ActionCable.server.stubs(:remote_connections).returns(remote_connections)

    untenanted do
      delete session_path
    end

    assert_equal [ leo, other_account_user ].map(&:id).sort, disconnected_users.map(&:id).sort,
      "sign-out must disconnect every per-account user of the signed-out identity"
    assert_equal [ true, true ], reconnect_flags,
      "reconnect must stay true so still-valid sessions on other devices recover"
  end

  test "destroy with an access token has no session to end and does not raise" do
    untenanted { delete session_path(format: :json), env: api_token_env }

    assert_response :no_content
  end
end
