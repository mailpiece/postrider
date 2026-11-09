require "test_helper"

class Mailpieces::QueuedsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :nonstaff
  end

  test "show lists the mail still on its way through, in either direction" do
    queued = [ mailpieces(:queued), create_inbound_email.mailpiece, create_inbound_email(status: :processing).mailpiece ]

    get mailpieces_queued_path

    assert_response :success
    queued.each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "show as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    hidden = deliver_from(domains(:private), status: "queued").mailpiece

    get mailpieces_queued_path, as: :json

    assert_response :success
    assert_includes response.parsed_body.pluck("id"), mailpieces(:queued).id
    assert_not_includes response.parsed_body.pluck("id"), hidden.id
  end
end
