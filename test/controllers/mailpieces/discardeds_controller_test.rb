require "test_helper"

class Mailpieces::DiscardedsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists the discarded mail" do
    discarded = create_inbound_email(status: :bounced).mailpiece

    get mailpieces_discarded_path

    assert_response :success
    assert_select "li##{dom_id(discarded)}"
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    discarded = create_inbound_email(status: :bounced).mailpiece
    hidden = create_inbound_email(domain: domains(:private), status: :bounced).mailpiece

    get mailpieces_discarded_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), discarded.id
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
