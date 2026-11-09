require "test_helper"

class SearchesControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :leo
  end

  test "show lists the mailpieces whose subject matches, in either direction" do
    received = create_inbound_email(raw: "Subject: March invoice\r\n\r\nBody").mailpiece
    sent = create_delivery(raw: "Subject: Your march receipt\r\n\r\nBody").mailpiece

    get search_path(q: "MARCH")

    [ received, sent ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "show lists the mailpieces whose sender matches, in either direction" do
    received = create_inbound_email(mail_from: "billing@vendor.example").mailpiece
    sent = create_delivery(mail_from: "billing@example.com").mailpiece

    get search_path(q: "BILLING")

    [ received, sent ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "show lists the mailpieces whose recipient matches, in either direction" do
    received = create_inbound_email(rcpt_to: "orders@example.com").mailpiece
    sent = create_delivery(rcpt_to: "orders@customer.example").mailpiece

    get search_path(q: "ORDERS")

    [ received, sent ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "show lists the contacts whose address matches" do
    get search_path(q: "FRIEND")

    assert_select "li##{dom_id(contacts(:approved))}"
  end

  test "show lists the domains whose name matches" do
    get search_path(q: "EXAM")

    assert_select "li##{dom_id(domains(:example))}"
  end

  test "show omits what is on a domain you cannot reach" do
    sign_out
    sign_in_as :nonstaff
    create_inbound_email(domain: domains(:private), raw: "Subject: Hidden private\r\n\r\nBody")

    get search_path(q: "hidden")
    assert_select "li.row", count: 0

    get search_path(q: "private")
    assert_select "li.row", count: 0
  end

  test "show pages the mailpieces" do
    16.times { create_inbound_email(raw: "Subject: Paged\r\n\r\nBody") }

    get search_path(q: "paged")

    assert_select "a.pagination-link[href=?]", search_path(q: "paged", page: 2)

    get search_path(q: "paged", page: 2)

    assert_select "a.pagination-link[href=?]", search_path(q: "paged", page: 3), count: 0
  end

  test "show with nothing matching says so" do
    get search_path(q: "nobody-by-this-name")

    assert_select ".blank-slate", text: "No matches"
  end

  test "show with no query lists nothing" do
    get search_path

    assert_select "li.row", count: 0
  end

  test "show as JSON lists the same records" do
    get search_path(q: "friend"), as: :json

    assert_response :success
    assert_equal [ mailpieces(:received).id ], response.parsed_body["mailpieces"].pluck("id")
    assert_equal [ contacts(:approved).id ], response.parsed_body["contacts"].pluck("id")
    assert_empty response.parsed_body["domains"]
  end
end
