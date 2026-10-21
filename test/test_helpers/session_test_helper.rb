module SessionTestHelper
  def parsed_cookies
    ActionDispatch::Cookies::CookieJar.build(request, cookies.to_hash)
  end

  def sign_in_as(identity)
    cookies.delete :session_token

    if identity.is_a?(User)
      user = identity
      identity = user.identity
      raise "User #{user.name} (#{user.id}) doesn't have an associated identity" unless identity
    elsif !identity.is_a?(Identity)
      identity = identities(identity)
    end

    untenanted do
      put session_transfer_path(identity.transfer_id)
    end

    assert_response :redirect, "Redeeming the transfer link should grant access"

    cookie = cookies.get_cookie "session_token"
    assert_not_nil cookie, "Expected session_token cookie to be set after sign in"
  end

  def logout_and_sign_in_as(identity)
    Session.delete_all
    sign_in_as identity
  end

  def confirm_sudo
    Session.find_signed(parsed_cookies.signed[:session_token]).sudo
  end

  def sign_out
    untenanted do
      delete session_path
    end
    assert_not cookies[:session_token].present?
  end

  def untenanted(&block)
    # integration_session is built on first read, and one built before the routes are
    # drawn has no mounted-engine proxies. Nothing else here forces them.
    Rails.application.reload_routes_unless_loaded

    original_options = integration_session.default_url_options
    integration_session.default_url_options = original_options.merge(script_name: "")
    yield
  ensure
    integration_session.default_url_options = original_options
  end

  def with_multi_tenant_mode(enabled)
    previous = Account.multi_tenant
    Account.multi_tenant = enabled
    yield
  ensure
    Account.multi_tenant = previous
  end
end
