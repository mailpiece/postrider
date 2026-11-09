require "test_helper"

class Contacts::DeniedsControllerTest < ActionDispatch::IntegrationTest
  test "show lists the screened-out senders" do
    sign_in_as :leo

    get contacts_denied_path

    assert_response :success
    assert_select "#contact_#{contacts(:denied).id}"
  end

  test "show screens a sender back in, asking first" do
    sign_in_as :leo

    get contacts_denied_path

    assert_select "form[action=?][data-turbo-confirm] button", contact_approval_path(contacts(:denied)), text: "Screen them in"
  end

  test "show lists a sender's held mail without a query per email" do
    sign_in_as :leo
    queries_for_one = count_queries { get contacts_denied_path }

    5.times { create_inbound_email(status: :held, contact: contacts(:denied), rcpt_to: "forwarding@example.com") }

    assert_equal queries_for_one, count_queries { get contacts_denied_path }
  end

  test "show offers an admin clearing all, asking first" do
    sign_in_as :leo

    get contacts_denied_path

    assert_select "form[action=?][data-turbo-confirm] button", contacts_screened_out_mail_path
  end

  test "show is fresh again once the mail from screened-out senders is erased" do
    sign_in_as :leo

    get contacts_denied_path
    users(:leo).erase_screened_out_mail_now
    get contacts_denied_path, headers: { "HTTP_IF_NONE_MATCH" => response.headers["ETag"] }

    assert_response :success
    assert_select "form[action=?]", contacts_screened_out_mail_path, count: 0
  end

  test "show offers no clearing to a member" do
    sign_in_as :nonstaff

    get contacts_denied_path

    assert_select "form[action=?]", contacts_screened_out_mail_path, count: 0
  end

  test "show renders json" do
    sign_in_as :leo

    get contacts_denied_path, as: :json

    assert_response :success
    assert_equal [ "denied" ], response.parsed_body.pluck("decision").uniq
    assert_equal 1, response.parsed_body.find { it["id"] == contacts(:denied).id }["held_count"]
  end

  test "show omits senders on a domain you cannot reach" do
    sign_in_as :nonstaff

    get contacts_denied_path, as: :json

    assert_includes response.parsed_body.pluck("id"), contacts(:denied).id
    assert_not_includes response.parsed_body.pluck("id"), contacts(:private).id
  end

  private
    def count_queries(&block)
      queries = []
      counter = ->(event) { queries << event.payload[:sql] unless event.payload[:cached] || event.payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      queries.size
    end
end
