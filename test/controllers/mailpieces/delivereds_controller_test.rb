require "test_helper"

class Mailpieces::DeliveredsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists the delivered mail in either direction and nothing else" do
    get mailpieces_delivered_path

    assert_response :success
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".breadcrumbs strong", text: "Delivered"
    assert_select ".breadcrumbs a[href=?]", root_path, text: "Mailpieces"
    assert_select ".status-filter__button", text: "Delivered"
    [ mailpieces(:delivered), mailpieces(:received) ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
    [ mailpieces(:held), mailpieces(:queued), mailpieces(:bounced), mailpieces(:deferred) ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}", count: 0 }
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    hidden = deliver_from(domains(:private), status: "delivered").mailpiece

    get mailpieces_delivered_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), mailpieces(:delivered).id
    assert_includes response.parsed_body.pluck("id"), mailpieces(:received).id
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
