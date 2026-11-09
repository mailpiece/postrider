require "test_helper"

class Mailpieces::FailedsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists mail that did not get through, in either direction" do
    failed = [ mailpieces(:bounced) ] + %i[ exhausted suppressed ].map { |status| create_delivery(status: status).mailpiece }
    failed << create_inbound_email(status: :failed).mailpiece

    get mailpieces_failed_path

    assert_response :success
    failed.each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
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
