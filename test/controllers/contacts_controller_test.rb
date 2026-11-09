require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  test "index lists the approved contacts" do
    sign_in_as :leo

    get contacts_path

    assert_response :success
    assert_select "li##{dom_id(contacts(:approved))}"
  end

  test "index says so when no contact is approved" do
    sign_in_as :leo
    contacts(:approved).deny

    get contacts_path

    assert_response :success
    assert_select ".blank-slate", text: /No contacts yet/
  end

  test "index as JSON lists the same contacts, leaving out one you cannot reach" do
    sign_in_as :leo
    contacts(:other_account).update!(decision: :approved)

    get contacts_path, as: :json

    assert_response :success
    assert_equal [ contacts(:approved).id ], response.parsed_body.pluck("id")
  end

  test "show lists the messages from the contact" do
    sign_in_as :leo
    create_inbound_email(status: :held, contact: contacts(:denied), raw: "Subject: Held hello\r\n\r\nBody")

    get contact_path(contacts(:denied))

    assert_response :success
    assert_select ".mailpiece__subject", text: "Held hello"
  end

  test "show offers to screen out an approved contact" do
    sign_in_as :leo

    get contact_path(contacts(:approved))

    assert_select "form[action=?]:has(input[name=_method][value=delete]) button", contact_approval_path(contacts(:approved)), text: "Screen them out"
  end

  test "show offers to screen in a denied contact, asking first" do
    sign_in_as :leo

    get contact_path(contacts(:denied))

    assert_select "form[action=?][data-turbo-confirm] button", contact_approval_path(contacts(:denied)), text: "Screen them in"
  end

  test "show offers a yes for a pending contact" do
    sign_in_as :leo

    get contact_path(contacts(:pending))

    assert_select "form[action=?] button", contact_approval_path(contacts(:pending)), text: "Yes"
  end

  test "show omits the mail of other contacts" do
    sign_in_as :leo
    create_inbound_email(status: :held, contact: contacts(:denied), raw: "Subject: Not theirs\r\n\r\nBody")

    get contact_path(contacts(:approved))

    assert_response :success
    assert_select ".mailpiece__subject", text: /Not theirs/, count: 0
  end

  test "show is not found for a contact on a domain you cannot reach" do
    sign_in_as :nonstaff
    get contact_path(contacts(:private))

    assert_response :not_found
  end

  test "show is not found for another account's contact" do
    sign_in_as :leo

    get contact_path(contacts(:other_account))

    assert_response :not_found
  end
end
