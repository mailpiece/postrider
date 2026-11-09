require "test_helper"

class ScreenersControllerTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  setup do
    sign_in_as :leo
    inbound_emails(:held).update!(contact: contacts(:pending), subject: "Quote for the roof")
  end

  test "show gives each waiting sender a row with a yes and a no" do
    get screener_path

    assert_response :success
    assert_select "form[action=?]:not(:has(input[name=_method])) button", contact_approval_path(contacts(:pending)), text: "Yes"
    assert_select "form[action=?]:has(input[name=_method][value=delete]) button", contact_approval_path(contacts(:pending)), text: "No"
  end

  test "show leaves out a sender known by address alone" do
    4.times { create_inbound_email(status: :held, contact: contacts(:pending)) }
    contacts(:pending).update!(name: nil)

    get screener_path

    assert_select "li.row", count: 1
  end

  test "show does not flag a sender whose spam check passed" do
    inbound_emails(:held).track_event "scored", action: "no_action", score: -1.8, complete: true, symbols: []

    get screener_path

    assert_select "h2", text: "Flagged by the spam check", count: 0
  end

  test "show lists the senders the spam check flagged apart" do
    flag_sender "bulk@sender.example"

    get screener_path

    assert_select "h2", text: "Flagged by the spam check"
  end

  test "show offers only screening out the flagged when everyone waiting is flagged" do
    inbound_emails(:held).track_event "scored", action: "reject", score: 12.0, complete: true, symbols: []

    get screener_path

    assert_select "form[action=?]", screener_flagged_denial_path
    assert_select "form[action=?]", screener_denial_path, count: 0
  end

  test "show lists everyone waiting on one page" do
    30.times { |i| flag_sender "sender#{i}@sender.example", action: "no_action", score: 0.1 }

    get screener_path

    assert_select "li.row", count: 31
  end

  test "show asks before screening out everyone waiting" do
    get screener_path

    assert_select "form[action=?][data-turbo-confirm] button", screener_denial_path
    assert_select "form[action=?]", screener_flagged_denial_path, count: 0
  end

  test "show is fresh again once a late spam check lands" do
    inbound_emails(:held).update!(raw: SIMPLE_RAW)

    get screener_path
    etag = response.headers["ETag"]

    get screener_path, headers: { "If-None-Match" => etag }
    assert_response :not_modified

    MailScore::Client.any_instance.stubs(:check).returns(MailScore::Client::Result.new(action: :reject, score: 7.4,
      complete: true, symbols: [], smtp_reply: nil, subject: nil, headers: []))
    inbound_emails(:held).score_now

    get screener_path, headers: { "If-None-Match" => etag }
    assert_response :success
  end

  test "show escapes a hostile name" do
    contacts(:pending).update!(name: "<script>alert(1)</script>")

    get screener_path

    assert_select "script", text: "alert(1)", count: 0
    assert_select ".row__title", text: /<script>alert\(1\)<\/script>/
  end

  test "show marks a look-alike address" do
    contacts(:pending).update!(lookalike: true)

    get screener_path

    assert_select "##{dom_id(contacts(:pending))} .row__title .envelope__phishing", text: "Phishing?"
  end

  test "show says so when nobody is waiting" do
    contacts(:pending).deny

    get screener_path

    assert_select ".blank-slate", text: /Nobody is waiting/
  end

  test "show renders json with the flagged among the rest" do
    flagged = flag_sender "bulk@sender.example"

    get screener_path, as: :json

    assert_response :success
    assert_equal [ flagged.id, contacts(:pending).id ], response.parsed_body.pluck("id")
    assert_equal [ "pending", "pending" ], response.parsed_body.pluck("decision")
  end

  private
    def flag_sender(email, action: "reject", score: 7.4)
      domains(:example).contacts.create!(email: email, decision: :pending).tap do |contact|
        email = create_inbound_email(status: :held, contact: contact, rcpt_to: "forwarding@example.com", raw: "Subject: 80% off everything\r\n\r\nOur biggest sale ends tonight.")
        email.track_event "scored", action: action, score: score, complete: true, symbols: []
      end
    end
end
