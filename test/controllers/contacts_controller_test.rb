require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  test "index lists the approved contacts as plain links" do
    sign_in_as :leo

    get contacts_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Contacts"
    assert_select "li##{dom_id(contacts(:approved))} a.row__body[href=?]", contact_path(contacts(:approved)), text: /Friend\s+friend@sender\.example/
    assert_select "li##{dom_id(contacts(:denied))}", count: 0
    assert_select "li##{dom_id(contacts(:pending))}", count: 0
    assert_select ".rows--links", count: 0
    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
  end

  test "index says so when no contact is approved" do
    sign_in_as :leo
    contacts(:approved).deny

    get contacts_path

    assert_response :success
    assert_select ".blank-slate", text: /No contacts yet/
  end

  test "the navigation's Contacts link opens the approved contacts" do
    sign_in_as :leo

    get contacts_path

    assert_select "a.site-header__link[href=?][aria-current=page]", contacts_path, text: /Contacts/
  end

  test "index links to the Screener and to Screened out" do
    sign_in_as :leo

    get contacts_path

    assert_select ".header__actions a[href=?]", screener_path, text: "Screener"
    assert_select ".header__actions a[href=?]", contacts_denied_path, text: "Screened out"
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
    assert_select ".envelope__subject", text: "Held hello"
    assert_select ".envelope__subject", text: "Forwarded hello"
  end

  test "show offers to screen out an approved contact" do
    sign_in_as :leo

    get contact_path(contacts(:approved))

    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".screener-question", text: /Their mail is forwarded to you\./
    assert_select "form[action=?]:has(input[name=_method][value=delete]) button", contact_approval_path(contacts(:approved)), text: "Screen them out"
  end

  test "show offers to screen in a denied contact, asking before it forwards held mail" do
    sign_in_as :leo

    get contact_path(contacts(:denied))

    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".breadcrumbs a[href=?]", contacts_denied_path, text: "Screened out"
    assert_select ".screener-question", text: /stranger@sender\.example is screened out\. Their mail is held and isn't forwarded unless you screen them in\./
    assert_select "form[action=?][data-turbo-confirm=?] button", contact_approval_path(contacts(:denied)),
      "Forward 1 held email from stranger@sender.example to forwarding@elsewhere.example?", text: "Screen them in"
  end

  test "show asks about a pending contact as the Screener does" do
    sign_in_as :leo

    get contact_path(contacts(:pending))

    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".breadcrumbs a[href=?]", screener_path, text: "The Screener"
    assert_select ".screener-question", text: /Newcomer is writing for the first time/
    assert_select ".screener-question form[action=?] button", contact_approval_path(contacts(:pending)), text: "Yes"
  end

  test "show omits the mail of other contacts" do
    sign_in_as :leo
    create_inbound_email(status: :held, contact: contacts(:denied), raw: "Subject: Not theirs\r\n\r\nBody")

    get contact_path(contacts(:approved))

    assert_response :success
    assert_select ".envelope__subject", text: /Not theirs/, count: 0
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
