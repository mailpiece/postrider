require "test_helper"

class Domains::SendingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "an admin turns sending off and goes back" do
    sign_in_as :leo

    delete domain_sending_path(@domain), headers: { "HTTP_REFERER" => edit_domain_path(@domain) }

    assert_redirected_to edit_domain_path(@domain)
    assert_not @domain.reload.sending?
  end

  test "an admin turns sending on" do
    sign_in_as :leo
    @domain.update!(sending: false)

    post domain_sending_path(@domain)

    assert @domain.reload.sending?
  end

  test "destroy json" do
    delete domain_sending_path(@domain), headers: api_token_env, as: :json

    assert_response :success
    assert_equal false, response.parsed_body["sending"]
    assert_not @domain.reload.sending?
  end

  test "a member is refused" do
    sign_in_as :nonstaff

    delete domain_sending_path(@domain)

    assert_response :forbidden
    assert @domain.reload.sending?
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    delete domain_sending_path(domains(:other_account))

    assert_response :not_found
  end
end
