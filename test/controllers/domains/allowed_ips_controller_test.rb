require "test_helper"

class Domains::AllowedIpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "an admin opens the allowed IPs" do
    @domain.update!(allowed_ips: "203.0.113.0/24")
    sign_in_as :leo
    confirm_sudo

    get domain_allowed_ips_path(@domain)

    assert_response :success
    assert_select "form[action=?] textarea", domain_allowed_ips_path(@domain), text: /203\.0\.113\.0\/24/
  end

  test "an admin saves the allowed IPs" do
    sign_in_as :leo
    confirm_sudo

    patch domain_allowed_ips_path(@domain), params: { domain: { allowed_ips: "203.0.113.0/24\r\n\r\n198.51.100.12" } }

    assert_redirected_to domain_path(@domain)
    assert_equal "203.0.113.0/24\n198.51.100.12", @domain.reload.allowed_ips
  end

  test "an IPv6 address is turned down in place, keeping what was typed" do
    sign_in_as :leo
    confirm_sudo

    patch domain_allowed_ips_path(@domain), params: { domain: { allowed_ips: "203.0.113.0/24\r\n2001:db8::1" } }

    assert_response :unprocessable_entity
    assert_select ".error-explanation__message", text: %(Allowed IPs can't hold "2001:db8::1": only IPv4 addresses and ranges)
    assert_select "textarea", text: /203\.0\.113\.0\/24\s+2001:db8::1/
    assert_nil @domain.reload.allowed_ips
  end

  test "changing the allowed IPs asks for a passkey first" do
    sign_in_as :leo

    patch domain_allowed_ips_path(@domain), params: { domain: { allowed_ips: "203.0.113.0/24" } }

    assert_redirected_to new_my_sudo_path
    assert_nil @domain.reload.allowed_ips
  end

  test "a member cannot change the allowed IPs" do
    sign_in_as :nonstaff

    patch domain_allowed_ips_path(@domain), params: { domain: { allowed_ips: "203.0.113.0/24" } }

    assert_response :forbidden
    assert_nil @domain.reload.allowed_ips
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    patch domain_allowed_ips_path(domains(:other_account)), params: { domain: { allowed_ips: "203.0.113.0/24" } }

    assert_response :not_found
  end
end
