require "test_helper"

class Mailpieces::HeldsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists the held mail and nothing else" do
    get mailpieces_held_path

    assert_response :success
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".breadcrumbs strong", text: "Held"
    assert_select ".breadcrumbs a[href=?]", root_path, text: "Mailpieces"
    assert_select "li##{dom_id(mailpieces(:held))}"
    assert_select "li##{dom_id(mailpieces(:received))}", count: 0
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    hidden = create_inbound_email(domain: domains(:private), status: :held).mailpiece

    get mailpieces_held_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), mailpieces(:held).id
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
