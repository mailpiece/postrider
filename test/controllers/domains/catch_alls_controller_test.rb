require "test_helper"

class Domains::CatchAllsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "edit has the one form, under Mailboxes" do
    sign_in_as :leo

    get edit_domain_catch_all_path(@domain)

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", domain_mailboxes_path(@domain), text: "Mailboxes"
    assert_select "form[action=?] select[name=?]", domain_catch_all_path(@domain), "domain[catch_all_policy]", count: 1
  end

  test "an admin changes the policy and goes back to the mailboxes" do
    sign_in_as :leo

    patch domain_catch_all_path(@domain), params: { domain: { catch_all_policy: "discard" } }

    assert_redirected_to domain_mailboxes_path(@domain)
    assert_equal "discard", @domain.reload.catch_all_policy
  end

  test "update json" do
    patch domain_catch_all_path(@domain), params: { catch_all_policy: "forward" }, headers: api_token_env, as: :json

    assert_response :success
    assert_equal "forward", response.parsed_body["catch_all_policy"]
    assert_equal "forward", @domain.reload.catch_all_policy
  end

  test "a member is refused" do
    sign_in_as :nonstaff

    get edit_domain_catch_all_path(@domain)
    assert_response :forbidden

    patch domain_catch_all_path(@domain), params: { domain: { catch_all_policy: "discard" } }
    assert_response :forbidden
    assert_equal "disabled", @domain.reload.catch_all_policy
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    patch domain_catch_all_path(domains(:other_account)), params: { domain: { catch_all_policy: "discard" } }

    assert_response :not_found
  end
end
