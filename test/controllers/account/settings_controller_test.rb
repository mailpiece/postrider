require "test_helper"

class Account::SettingsControllerTest < ActionDispatch::IntegrationTest
  test "show offers the owner deleting the account" do
    with_multi_tenant_mode(true) do
      sign_in_as :leo

      get account_settings_path

      assert_response :success
      assert_select "li.row a[href=?]", new_account_cancellation_path
    end
  end

  test "show omits deleting the account where it cannot be deleted" do
    with_multi_tenant_mode(false) do
      sign_in_as :leo

      get account_settings_path

      assert_select "li.row a[href=?]", new_account_cancellation_path, count: 0
    end
  end

  test "show offers a member no configuration" do
    sign_in_as :nonstaff

    get account_settings_path

    assert_response :success
    assert_select "li.row a[href=?]", edit_account_name_path, count: 0
    assert_select "li.row a[href=?]", edit_account_bounce_routing_path, count: 0
    assert_select "li.row a[href=?]", new_account_cancellation_path, count: 0
  end

  test "show json" do
    sign_in_as :nonstaff

    get account_settings_path, as: :json

    assert_response :success
    assert_equal accounts(:davids_account).name, response.parsed_body["name"]
  end

  test "the footer doesn't link staff to the adminland" do
    sign_in_as :leo

    get account_settings_path

    assert_select "a[href=?]", adminland_settings_path(script_name: nil), count: 0
  end
end
