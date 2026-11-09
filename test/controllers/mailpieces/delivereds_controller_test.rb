require "test_helper"

class Mailpieces::DeliveredsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists the delivered mail in either direction" do
    get mailpieces_delivered_path

    assert_response :success
    [ mailpieces(:delivered), mailpieces(:received) ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
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
