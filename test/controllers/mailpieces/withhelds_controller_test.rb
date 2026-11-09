require "test_helper"

class Mailpieces::WithheldsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists mail withheld for a blocked phrase" do
    withheld = create_delivery(status: :withheld).mailpiece

    get mailpieces_withheld_path

    assert_response :success
    assert_select "li##{dom_id(withheld)}"
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    withheld = create_delivery(status: :withheld).mailpiece
    hidden = deliver_from(domains(:private), status: "withheld").mailpiece

    get mailpieces_withheld_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), withheld.id
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
