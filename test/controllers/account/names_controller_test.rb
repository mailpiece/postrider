require "test_helper"

class Account::NamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
    @account = accounts(:davids_account)
  end

  test "edit has the one form, under Settings" do
    get edit_account_name_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", account_settings_path, text: "Settings"
    assert_select "form[action=?]", account_name_path, count: 1
    assert_select "input[name='account[name]'][value=?][placeholder=?]", @account.name, "Account name…"
  end

  test "update goes back to Settings" do
    patch account_name_path, params: { account: { name: "Renamed" } }

    assert_redirected_to account_settings_path
    assert_equal "Settings saved", flash[:notice]
    assert_equal "Renamed", @account.reload.name
  end

  test "update json" do
    patch account_name_path, params: { name: "Renamed" }, as: :json

    assert_response :no_content
    assert_equal "Renamed", @account.reload.name
  end

  test "update refuses a blank name" do
    assert_no_changes -> { @account.reload.name } do
      patch account_name_path, params: { account: { name: " " } }
    end

    assert_response :unprocessable_entity
    assert_select ".error-explanation"
    assert_select "form[action=?]", account_name_path
  end

  test "members are refused" do
    sign_out
    sign_in_as :nonstaff

    get edit_account_name_path
    assert_response :forbidden

    assert_no_changes -> { @account.reload.name } do
      patch account_name_path, params: { account: { name: "Mine" } }
    end
    assert_response :forbidden
  end
end
