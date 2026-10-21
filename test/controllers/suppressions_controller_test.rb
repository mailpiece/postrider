require "test_helper"

class SuppressionsControllerTest < ActionDispatch::IntegrationTest
  test "index lists the suppressions on domains you can reach" do
    sign_in_as :leo

    get suppressions_path

    assert_response :success
    assert_select "form[action=?]", suppression_path(suppressions(:bounced))
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".row__title", text: "invalid@unreachable.example"
    assert_select ".breadcrumbs a[href=?]", account_settings_path, text: "Settings"
    assert_select ".site-header__link[aria-current=page][href=?]", account_settings_path
  end

  test "index renders json" do
    sign_in_as :leo

    get suppressions_path, as: :json

    assert_response :success
    entry = response.parsed_body.find { |listed| listed["address"] == "invalid@unreachable.example" }
    assert_equal "invalid", entry["reason"]
  end

  test "index omits suppressions on a domain you cannot reach" do
    sign_in_as :nonstaff
    domains(:private).suppressions.create!(address: "hidden@example.com", reason: "hard bounce")

    get suppressions_path, as: :json

    assert_response :success
    assert_empty response.parsed_body.select { |listed| listed["address"] == "hidden@example.com" }
  end

  test "destroy removes a suppression" do
    sign_in_as :leo

    assert_difference -> { domains(:example).suppressions.count }, -1 do
      delete suppression_path(suppressions(:bounced))
    end

    assert_redirected_to suppressions_path
  end

  test "a member can neither remove a suppression nor see the button to" do
    sign_in_as :nonstaff
    suppression = suppressions(:bounced)

    get suppressions_path
    assert_select ".row__title", text: "invalid@unreachable.example"
    assert_select "form[action=?]", suppression_path(suppression), count: 0

    delete suppression_path(suppression)

    assert_response :forbidden
    assert Suppression.exists?(suppression.id)
  end

  test "destroy cannot remove a suppression on a domain you cannot reach" do
    users(:nonstaff).update!(role: :admin)
    sign_in_as :nonstaff
    suppression = domains(:private).suppressions.create!(address: "hidden@example.com")

    delete suppression_path(suppression)

    assert_response :not_found
    assert Suppression.exists?(suppression.id)
  end

  test "destroy cannot remove another account's suppression" do
    sign_in_as :leo
    suppression = domains(:other_account).suppressions.create!(address: "bounced@other.example")

    delete suppression_path(suppression)

    assert_response :not_found
  end
end
