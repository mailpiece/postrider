require "test_helper"

class Contacts::PendingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :leo
  end

  test "show lists the pending contacts with a yes and a no" do
    get contacts_pending_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "The Screener"
    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".row__title", text: /newcomer@sender\.example/
    assert_select ".row__title", text: /stranger@sender\.example/, count: 0
    assert_select "form[action=?]:has(input[name=_method][value=delete]) button", contact_approval_path(contacts(:pending)), text: "No"
    assert_select "form[action=?]:not(:has(input[name=_method])) button", contact_approval_path(contacts(:pending)), text: "Yes"
  end

  test "show asks before clearing everyone waiting" do
    get contacts_pending_path

    assert_select "form[action=?][data-turbo-confirm=?] button", contacts_pending_denial_path,
      "Move all 1 waiting sender to Screened out? Their mail stays held, and you can still switch any of them on from their page.", text: "Clear all…"
  end

  test "show gives the latest held email's subject" do
    held = inbound_emails(:held)
    held.update!(contact: contacts(:pending), subject: "Quote for the roof")

    get contacts_pending_path

    assert_select ".row__meta", text: "Quote for the roof"
    assert_select ".row__meta", text: /1 email held/
  end

  test "show escapes a hostile name and subject" do
    contacts(:pending).update!(name: "<script>alert(1)</script>")
    inbound_emails(:held).update!(contact: contacts(:pending), subject: "<img src=x onerror=alert(2)>")

    get contacts_pending_path

    assert_select "script", text: "alert(1)", count: 0
    assert_select "img[onerror]", count: 0
    assert_select ".row__title", text: /<script>alert\(1\)<\/script>/
  end

  test "show marks a look-alike address" do
    contacts(:pending).update!(lookalike: true)

    get contacts_pending_path

    assert_select ".row__title .envelope__phishing", text: "Phishing?"
  end

  test "show says so when nobody is waiting" do
    contacts(:pending).deny

    get contacts_pending_path

    assert_select ".blank-slate", text: /Nobody is waiting/
    assert_select "form[action=?]", contacts_pending_denial_path, count: 0
  end

  test "show renders json" do
    get contacts_pending_path, as: :json

    assert_response :success
    assert_equal [ contacts(:pending).id ], response.parsed_body.pluck("id")
    assert_equal [ "pending" ], response.parsed_body.pluck("decision")
  end
end
