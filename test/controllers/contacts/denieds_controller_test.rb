require "test_helper"

class Contacts::DeniedsControllerTest < ActionDispatch::IntegrationTest
  test "show lists the denied contacts on domains you can reach" do
    sign_in_as :leo

    get contacts_denied_path

    assert_response :success
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".row__title", text: /stranger@sender\.example/
    assert_select ".row__title", text: /friend@sender\.example/, count: 0
  end

  test "show renders json" do
    sign_in_as :leo

    get contacts_denied_path, as: :json

    assert_response :success
    assert_equal [ "denied" ], response.parsed_body.pluck("decision").uniq
    assert_includes response.parsed_body.pluck("email"), "stranger@sender.example"
  end

  test "show omits contacts on a domain you cannot reach" do
    sign_in_as :nonstaff

    get contacts_denied_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("email"), "stranger@sender.example"
    assert_not_includes response.parsed_body.pluck("email"), contacts(:private).email
  end
end
