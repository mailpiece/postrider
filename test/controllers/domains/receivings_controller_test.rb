require "test_helper"

class Domains::ReceivingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "an admin turns receiving off and goes back" do
    sign_in_as :leo

    delete domain_receiving_path(@domain), headers: { "HTTP_REFERER" => edit_domain_path(@domain) }

    assert_redirected_to edit_domain_path(@domain)
    assert_not @domain.reload.receiving?
  end

  test "an admin turns receiving on" do
    sign_in_as :leo
    @domain.update!(receiving: false)

    post domain_receiving_path(@domain)

    assert @domain.reload.receiving?
  end

  test "destroy json" do
    delete domain_receiving_path(@domain), headers: api_token_env, as: :json

    assert_response :success
    assert_equal false, response.parsed_body["receiving"]
    assert_not @domain.reload.receiving?
  end

  test "a member is refused" do
    sign_in_as :nonstaff

    delete domain_receiving_path(@domain)

    assert_response :forbidden
    assert @domain.reload.receiving?
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    delete domain_receiving_path(domains(:other_account))

    assert_response :not_found
  end
end
