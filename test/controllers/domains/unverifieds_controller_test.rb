require "test_helper"

class Domains::UnverifiedsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :leo
  end

  test "show lists the domains not verified, checked or not, and nothing else" do
    missing = Current.account.domains.create!(name: "missing.example", creator: users(:leo), dkim_status: :missing)

    get domains_unverified_path

    assert_response :success
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".breadcrumbs strong", text: "Not verified"
    assert_select ".breadcrumbs a[href=?]", domains_path, text: "Domains"
    [ missing, domains(:unverified) ].each { |domain| assert_select "li##{dom_id(domain)}" }
    assert_select "li##{dom_id(domains(:example))}", count: 0
  end

  test "show says so when every domain is verified" do
    domains(:unverified).update!(dkim_status: :ok)

    get domains_unverified_path

    assert_response :success
    assert_select ".blank-slate", text: "Every domain is verified."
  end

  test "show as JSON lists the same domains, leaving out one you cannot reach" do
    domains(:other_account).update!(dkim_status: :missing)

    get domains_unverified_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), domains(:unverified).id
    assert_not_includes response.parsed_body.pluck("id"), domains(:example).id
    assert_not_includes response.parsed_body.pluck("id"), domains(:other_account).id
  end
end
