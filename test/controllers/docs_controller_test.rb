require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "the docs page renders with no real credentials in it" do
    sign_in_as :nonstaff

    get docs_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", account_settings_path, text: "Settings"
    assert_select ".site-header__link[aria-current=page][href=?]", account_settings_path
    assert_includes response.body, "YOUR_ACCESS_TOKEN"
    assert_includes response.body, "curl http://www.example.com/#{accounts(:davids_account).external_account_id}/messages"
    assert_not_includes response.body, "test_token_davids_api_0000000000"
    assert_includes response.body, "<code>invalid</code> is the only value that means the address itself is bad"
  end
end
