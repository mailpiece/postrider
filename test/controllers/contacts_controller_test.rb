require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  test "index lists the approved contacts and nothing else" do
    sign_in_as :leo

    get contacts_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Contacts"
    assert_select "li##{dom_id(contacts(:approved))}"
    assert_select "##{dom_id(contacts(:approved), :approval)}[checked]"
    assert_select "li##{dom_id(contacts(:denied))}", count: 0
  end

  test "index counts the denied contacts, over the list" do
    sign_in_as :leo

    get contacts_path

    assert_select ".rows--links a[href=?]", contacts_denied_path, text: "Denied"
    assert_select ".rows--links .row__end", text: "2"
    assert_select ".rows--links + .rows__section .rows__heading", text: "Approved"
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
  end

  test "index says so when no contact is approved" do
    sign_in_as :leo
    contacts(:approved).deny

    get contacts_path

    assert_response :success
    assert_select ".blank-slate", text: "No approved contacts."
    assert_select ".rows--links a[href=?]", contacts_denied_path
    assert_select ".rows--links + .blank-slate"
  end

  test "the navigation's Contacts link opens the approved contacts" do
    sign_in_as :leo

    get contacts_path

    assert_select "a.site-header__link[href=?][aria-current=page]", contacts_path, text: /Contacts/
  end

  test "index as JSON lists the same contacts, leaving out one you cannot reach" do
    sign_in_as :leo
    contacts(:other_account).update!(decision: :approved)

    get contacts_path, as: :json

    assert_response :success
    assert_equal [ contacts(:approved).id ], response.parsed_body.pluck("id")
  end

  test "show lists every message from the contact" do
    sign_in_as :leo
    create_inbound_email(status: :held, contact: contacts(:denied), raw: "Subject: Held hello\r\n\r\nBody")
    create_inbound_email(status: :delivered, contact: contacts(:denied), raw: "Subject: Forwarded hello\r\n\r\nBody")

    get contact_path(contacts(:denied))

    assert_response :success
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".row__title", text: /Held hello/
    assert_select ".row__title", text: /Forwarded hello/
  end

  test "show omits the mail of other contacts" do
    sign_in_as :leo
    create_inbound_email(status: :held, contact: contacts(:denied), raw: "Subject: Not theirs\r\n\r\nBody")

    get contact_path(contacts(:approved))

    assert_response :success
    assert_select ".row__title", text: /Not theirs/, count: 0
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
