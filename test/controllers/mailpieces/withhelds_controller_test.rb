require "test_helper"

class Mailpieces::WithheldsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists mail withheld for a blocked phrase and nothing that failed" do
    withheld = create_delivery(status: :withheld).mailpiece
    suppressed = create_delivery(status: :suppressed).mailpiece
    bounced = mailpieces(:bounced)

    get mailpieces_withheld_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Withheld"
    assert_select ".breadcrumbs a[href=?]", root_path, text: "Mailpieces"
    assert_select "li##{dom_id(withheld)}"
    assert_select "li##{dom_id(suppressed)}", count: 0
    assert_select "li##{dom_id(bounced)}", count: 0
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
