require "test_helper"

class ScreenersControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :leo
    inbound_emails(:held).update!(contact: contacts(:pending), subject: "Quote for the roof")
  end

  test "show gives each waiting sender a card with a yes and a no" do
    get screener_path

    assert_response :success
    assert_select ".breadcrumbs a[href=?]", contacts_path, text: "Contacts"
    assert_select ".breadcrumbs strong", text: "The Screener"
    assert_select "a.site-header__link[href=?][aria-current=page]", contacts_path
    assert_select "##{dom_id(contacts(:pending))} .screener-card__who", text: /Newcomer.*1 email held/m
    assert_select "##{dom_id(contacts(:pending))} .envelope__tab", text: /forwarding@example\.com/
    assert_select "##{dom_id(contacts(:denied))}", count: 0
    assert_select "form[action=?]:has(input[name=_method][value=delete]) button", contact_approval_path(contacts(:pending)), text: "No"
    assert_select "form[action=?]:not(:has(input[name=_method])) button", contact_approval_path(contacts(:pending)), text: "Yes"
  end

  test "show lists the sender's held mail, each opening its mailpiece" do
    get screener_path

    assert_select ".screener-card__email[href=?]", mailpiece_path(mailpieces(:held)), text: /Quote for the roof/
    assert_select ".screener-card__more", count: 0
  end

  test "show links to the sender's page past three held emails" do
    3.times { create_inbound_email(status: :held, contact: contacts(:pending)) }

    get screener_path

    assert_select ".screener-card__email", count: 3
    assert_select ".screener-card__more a[href=?]", contact_path(contacts(:pending)), text: "See all 4 emails from this sender"
  end

  test "show asks before screening out everyone waiting" do
    get screener_path

    assert_select "form[action=?][data-turbo-confirm=?] button", screener_denial_path,
      "Move all 1 waiting sender to Screened out? Their mail stays held, and you can still screen any of them in from their page.", text: "Screen out all…"
  end

  test "show escapes a hostile name and subject" do
    contacts(:pending).update!(name: "<script>alert(1)</script>")
    inbound_emails(:held).update!(subject: "<img src=x onerror=alert(2)>")

    get screener_path

    assert_select "script", text: "alert(1)", count: 0
    assert_select "img[onerror]", count: 0
    assert_select ".screener-card__who", text: /<script>alert\(1\)<\/script>/
  end

  test "show marks a look-alike address" do
    contacts(:pending).update!(lookalike: true)

    get screener_path

    assert_select ".screener-card__who .envelope__phishing", text: "Phishing?"
  end

  test "show says so when nobody is waiting" do
    contacts(:pending).deny

    get screener_path

    assert_select ".blank-slate", text: /Nobody is waiting/
    assert_select "form[action=?]", screener_denial_path, count: 0
  end

  test "show renders json" do
    get screener_path, as: :json

    assert_response :success
    assert_equal [ contacts(:pending).id ], response.parsed_body.pluck("id")
    assert_equal [ "pending" ], response.parsed_body.pluck("decision")
  end
end
