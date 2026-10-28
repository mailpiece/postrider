require "test_helper"

class Domains::BulksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @domain = domains(:example)
  end

  test "an admin turns bulk mail on and goes back" do
    sign_in_as :leo

    post domain_bulk_path(@domain), headers: { "HTTP_REFERER" => edit_domain_path(@domain) }

    assert_redirected_to edit_domain_path(@domain)
    assert @domain.reload.bulk?
  end

  test "an admin turns bulk mail off" do
    sign_in_as :leo
    @domain.update!(bulk: true)

    delete domain_bulk_path(@domain)

    assert_not @domain.reload.bulk?
  end

  test "create json" do
    post domain_bulk_path(@domain), headers: api_token_env, as: :json

    assert_response :success
    assert_equal true, response.parsed_body["bulk"]
    assert @domain.reload.bulk?
  end

  test "a member is refused" do
    sign_in_as :nonstaff

    post domain_bulk_path(@domain)

    assert_response :forbidden
    assert_not @domain.reload.bulk?
  end

  test "another account's domain cannot be reached" do
    sign_in_as :leo

    post domain_bulk_path(domains(:other_account))

    assert_response :not_found
  end
end
