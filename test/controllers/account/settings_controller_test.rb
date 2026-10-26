require "test_helper"

class Account::SettingsControllerTest < ActionDispatch::IntegrationTest
  test "show lists a row for each page, with how it stands" do
    with_multi_tenant_mode(true) do
      sign_in_as :leo

      get account_settings_path

      assert_response :success
      assert_select "ul.rows li.row", count: 7
      assert_select "li.row a[href=?]", edit_account_name_path, text: /Account\s+#{Regexp.escape(accounts(:davids_account).name)}/
      assert_select "li.row a[href=?]", edit_account_bounce_routing_path, text: /Bounce routing/
      assert_select "li.row a[href=?]", users_path, text: /People\s+\d+ pe/
      assert_select "li.row a[href=?]", suppressions_path, text: /Suppressions/
      assert_select "li.row a[href=?]", docs_path, text: /Docs/
      assert_select "li.row a[href=?]", user_path(users(:leo)), text: /Profile\s+Leo/
      assert_select "li.row a[href=?]", new_account_cancellation_path, text: /Delete account/
      assert_select "li.row .icon", count: 7
      assert_select "form[method=post]", count: 0
      assert_select ".site-header__link[aria-current=page][href=?]", account_settings_path, text: /Settings/
    end
  end

  test "show omits deleting the account where it cannot be deleted" do
    with_multi_tenant_mode(false) do
      sign_in_as :leo

      get account_settings_path

      assert_select "li.row a[href=?]", new_account_cancellation_path, count: 0
    end
  end

  test "show gives a member only the rows a member can open" do
    sign_in_as :nonstaff

    get account_settings_path

    assert_response :success
    assert_select "li.row a[href=?]", edit_account_name_path, count: 0
    assert_select "li.row a[href=?]", edit_account_bounce_routing_path, count: 0
    assert_select "li.row a[href=?]", new_account_cancellation_path, count: 0
    assert_select "li.row a[href=?]", users_path
    assert_select "li.row a[href=?]", suppressions_path
    assert_select "li.row a[href=?]", docs_path
    assert_select "li.row a[href=?]", user_path(users(:nonstaff)), text: /Profile\s+Non Staff/
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
