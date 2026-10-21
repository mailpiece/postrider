require "test_helper"

class Mailpieces::FailedsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists mail that did not get through, in either direction" do
    failed = [ mailpieces(:bounced) ] + %i[ exhausted suppressed ].map { |status| create_delivery(status: status).mailpiece }
    withheld = create_delivery(status: :withheld).mailpiece
    failed << create_inbound_email(status: :failed).mailpiece
    discarded = create_inbound_email(raw: "Subject: Discarded\r\n\r\nBody", status: :bounced).mailpiece
    delivered = mailpieces(:delivered)

    get mailpieces_failed_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Failed"
    assert_select ".breadcrumbs a[href=?]", root_path, text: "Mailpieces"
    failed.each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
    assert_select "li##{dom_id(discarded)}", count: 0
    assert_select "li##{dom_id(withheld)}", count: 0
    assert_select "li##{dom_id(delivered)}", count: 0
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    failed = [ mailpieces(:bounced), create_inbound_email(status: :failed).mailpiece ]
    hidden = deliver_from(domains(:private), status: "exhausted").mailpiece

    get mailpieces_failed_path, as: :json

    assert_response :success
    failed.each { |mailpiece| assert_includes response.parsed_body.pluck("id"), mailpiece.id }
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
