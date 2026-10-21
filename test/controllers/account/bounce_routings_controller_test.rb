require "test_helper"

class Account::BounceRoutingsControllerTest < ActionDispatch::IntegrationTest
  test "edit has the one form, under Settings" do
    sign_in_as :leo

    get edit_account_bounce_routing_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", account_settings_path, text: "Settings"
    assert_select "form[action=?]", account_bounce_routing_path, count: 1
    assert_select "input[name='setting[bounce_address]']"
  end

  test "admins can update the bounce address" do
    sign_in_as :leo

    patch account_bounce_routing_path, params: { setting: { bounce_address: "bounces@lists.example.com" } }

    assert_redirected_to account_settings_path
    assert_equal "Settings saved", flash[:notice]
    assert_equal "bounces@lists.example.com", Current.account.setting.reload.bounce_address
  end

  test "non-admins cannot see or update the bounce address" do
    sign_in_as :nonstaff
    setting = Current.account.setting
    setting.update!(bounce_address: "original@lists.example.com")

    get edit_account_bounce_routing_path
    assert_response :forbidden

    patch account_bounce_routing_path, params: { setting: { bounce_address: "hijack@evil.example.com" } }

    assert_response :forbidden
    assert_equal "original@lists.example.com", setting.reload.bounce_address
  end
end
