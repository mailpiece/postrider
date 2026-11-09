require "test_helper"

class MailpiecesControllerTest < ActionDispatch::IntegrationTest
  test "visiting root without an account slug redirects to the session menu" do
    sign_in_as :nonstaff

    get "/"

    assert_redirected_to "/session/menu"
  end

  test "the app opens on all the mail, in either direction and whatever became of it" do
    sign_in_as :nonstaff
    failed = create_inbound_email(status: :failed).mailpiece
    discarded = create_inbound_email(status: :bounced).mailpiece
    pieces = [ mailpieces(:delivered), mailpieces(:received), mailpieces(:held), mailpieces(:queued), mailpieces(:bounced),
      mailpieces(:deferred), failed, discarded ]

    get root_path

    assert_response :success
    pieces.each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "index with a verified domain but no mail says to send something from it" do
    sign_in_as :nonstaff
    Mailpiece.delete_all

    get mailpieces_path

    assert_response :success
    assert_select ".blank-slate", text: "No mail yet for example.com. Send something from it, or set up a mailbox."
  end

  test "index with an unverified domain and no mail says to publish its DNS records, before any verified one" do
    sign_in_as :nonstaff
    Mailpiece.delete_all
    domains(:unverified).accesses.grant_to [ users(:nonstaff) ]

    get mailpieces_path

    assert_select ".blank-slate", text: "No mail yet. Publish the DNS records of unverified.example and send something."
  end

  test "index with no domain offers an admin to add one" do
    sign_in_as :leo
    users(:leo).accesses.delete_all

    get mailpieces_path

    assert_select ".blank-slate a[href=?]", new_domain_path, text: "Add a domain"
  end

  test "index with no domain offers a member no button" do
    sign_in_as :nonstaff
    users(:nonstaff).accesses.delete_all

    get mailpieces_path

    assert_select ".blank-slate a[href=?]", new_domain_path, count: 0
  end

  test "index is fresh again once a domain is added" do
    sign_in_as :leo
    users(:leo).accesses.delete_all

    get mailpieces_path
    users(:leo).account.domains.create!(name: "added.example", creator: users(:leo))
    get mailpieces_path, headers: { "HTTP_IF_NONE_MATCH" => response.headers["ETag"] }

    assert_response :success
    assert_select ".blank-slate", text: "No mail yet. Publish the DNS records of added.example and send something."
  end

  test "index lists mail that was never delivered" do
    sign_in_as :nonstaff
    Mailpiece.where.not(id: mailpieces(:queued).id).delete_all

    get mailpieces_path

    assert_response :success
    assert_select "li##{dom_id mailpieces(:queued)}"
  end

  test "index by status lists the mail of that status, in either direction" do
    sign_in_as :nonstaff
    withheld = create_delivery(status: :withheld).mailpiece
    discarded = create_inbound_email(status: :bounced).mailpiece
    queued = [ mailpieces(:queued), create_inbound_email.mailpiece, create_inbound_email(status: :processing).mailpiece ]
    failed = [ mailpieces(:bounced), create_delivery(status: :exhausted).mailpiece, create_delivery(status: :suppressed).mailpiece,
      create_inbound_email(status: :failed).mailpiece ]

    {
      "delivered" => [ mailpieces(:delivered), mailpieces(:received) ], "held" => [ mailpieces(:held) ], "queued" => queued,
      "deferred" => [ mailpieces(:deferred) ], "failed" => failed, "withheld" => [ withheld ], "discarded" => [ discarded ]
    }.each do |status, listed|
      get mailpieces_path(status: status)

      assert_response :success
      listed.each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
      assert_select "li##{dom_id(mailpieces(:held))}", count: 0 unless status == "held"
    end
  end

  test "index by a status nothing has says so, not how to get started" do
    sign_in_as :nonstaff
    Mailpiece.where.not(id: mailpieces(:delivered).id).delete_all

    get mailpieces_path(status: "held")

    assert_response :success
    assert_select "li##{dom_id mailpieces(:delivered)}", count: 0
    assert_select ".blank-slate"
    assert_select ".blank-slate a[href=?]", domain_path(domains(:example)), count: 0
  end

  test "index by an unknown status lists all the mail" do
    sign_in_as :nonstaff

    get mailpieces_path(status: "nonsense")

    assert_response :success
    [ mailpieces(:delivered), mailpieces(:held), mailpieces(:queued) ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "index by all lists all the mail" do
    sign_in_as :nonstaff

    get mailpieces_path(status: "all")

    assert_response :success
    [ mailpieces(:delivered), mailpieces(:held), mailpieces(:queued) ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
  end

  test "index offers each status to choose from" do
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "form[action=?] [role=checkbox]", root_path, count: Mailpiece::STATUSES.size
  end

  test "index by status as JSON lists that status, leaving out a domain you cannot reach" do
    sign_in_as :nonstaff
    hidden = create_inbound_email(domain: domains(:private), status: :held).mailpiece

    get mailpieces_path(status: "held"), as: :json

    assert_response :success
    ids = response.parsed_body.pluck("id")
    assert_includes ids, mailpieces(:held).id
    assert_not_includes ids, mailpieces(:delivered).id
    assert_not_includes ids, hidden.id
  end

  test "index as JSON lists all the mail, leaving out a domain you cannot reach" do
    sign_in_as :nonstaff
    hidden = deliver_from(domains(:private), status: "delivered").mailpiece

    get mailpieces_path, as: :json

    assert_response :success
    ids = response.parsed_body.pluck("id")
    [ mailpieces(:delivered), mailpieces(:received), mailpieces(:held), mailpieces(:queued) ].each { |mailpiece| assert_includes ids, mailpiece.id }
    assert_not_includes ids, hidden.id
  end

  test "the HTML show renders a delivery-backed mailpiece" do
    messages(:queued).update!(raw: file_fixture("raw.eml").read)
    sign_in_as :nonstaff

    get mailpiece_path(mailpieces(:queued))

    assert_response :success
    assert_includes response.body, "Hello there."
  end

  test "an admin sees the phrase a delivery was withheld for" do
    delivery = deliveries(:queued)
    delivery.withhold("free money")

    sign_in_as :leo

    get mailpiece_path(delivery.mailpiece)

    assert_includes response.body, "Blocked mail to recipient@example.com because it contains the blocked phrase &quot;free money&quot;"

    get mailpiece_path(delivery.mailpiece), as: :json

    assert_equal "free money", response.parsed_body["events"].sole["particulars"]["phrase"]
  end

  test "a member sees that a delivery was withheld, but not the phrase or that one was the cause" do
    delivery = deliveries(:queued)
    delivery.withhold("s3cret phrase")

    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_includes response.body, "Blocked mail to recipient@example.com"
    assert_not_includes response.body, "s3cret phrase"
    assert_not_includes response.body, "blocked phrase"

    get mailpiece_path(delivery.mailpiece), as: :json

    assert_equal({ "rcpt_to" => "recipient@example.com" }, response.parsed_body["events"].sole["particulars"])
  end

  test "the JSON show renders a delivery-backed mailpiece with its direction and id" do
    get mailpiece_path(mailpieces(:queued)), headers: api_token_env, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "outbound", body["direction"]
    assert_equal mailpieces(:queued).id, body["id"]
  end

  test "the HTML show renders an inbound-backed mailpiece" do
    inbound_emails(:received).raw = file_fixture("raw.eml").read
    sign_in_as :nonstaff

    get mailpiece_path(mailpieces(:received))

    assert_response :success
    assert_includes response.body, "Hello there."
  end

  test "the HTML show renders an inbound-backed mailpiece nested too deep to parse" do
    mailpiece = create_inbound_email(raw: deeply_nested_raw).mailpiece
    sign_in_as :leo

    get mailpiece_path(mailpiece)

    assert_response :success
  end

  test "a look-alike sender shows as punycode, flagged as phishing" do
    lookalike = create_inbound_email(mail_from: "receipts@str\u0456pe.com", status: :held)
    normal = create_inbound_email(mail_from: "receipts@stripe.com", status: :held)
    sign_in_as :nonstaff

    get mailpiece_path(lookalike.mailpiece)
    assert_select ".envelope__return strong", text: "Phishing? receipts@xn--strpe-p2e.com"

    get mailpieces_path

    get mailpiece_path(normal.mailpiece)
  end

  test "the JSON show leaves out an inbound mailpiece's spam verdict" do
    inbound_email = create_inbound_email
    inbound_email.track_event "scored", action: "reject", score: 20.0, complete: true, symbols: []
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece, format: :json)

    assert_response :success
    assert_not_includes response.body, "reject"
  end

  # It reads as protocol output, and the badges above already answer what a human is asking.
  test "the HTML show keeps the raw results header out of the admin UI" do
    inbound_email = create_inbound_email(spf: "pass",
      authentication_results: "mx.test; spf=pass smtp.mailfrom=a@example.com")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_no_match "smtp.mailfrom", response.body
  end

  # "Held" beside a wall of passing checks reads as a contradiction until it says which gate failed.

  test "the HTML show offers a yes for a sender writing for the first time" do
    inbound_emails(:held).update!(contact: contacts(:pending))
    sign_in_as :leo

    get mailpiece_path(mailpieces(:held))

    assert_select "form[action=?] button", contact_approval_path(contacts(:pending)), text: "Yes"

    inbound_emails(:held).update!(contact: contacts(:approved))
    get mailpiece_path(mailpieces(:held))

    assert_select ".screener-question", count: 0
  end

  test "the HTML show offers to screen a screened-out sender back in" do
    sign_in_as :leo

    get mailpiece_path(mailpieces(:held))

    assert_select "form[action=?][data-turbo-confirm] button", contact_approval_path(contacts(:denied)), text: "Screen them in"
  end

  test "the HTML show leaves the screening banner off mail that was forwarded before its sender was screened out" do
    forwarded = create_inbound_email(status: :delivered, forwarded_at: Time.current, contact: contacts(:denied))
    sign_in_as :leo

    get mailpiece_path(forwarded.mailpiece)

    assert_response :success
    assert_select ".screener-question", count: 0
  end

  test "the HTML show links a matched bounce to the delivery it bounced" do
    delivery = deliveries(:bounced)
    sign_in_as :nonstaff

    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      inbound_email = create_inbound_email(rcpt_to: Delivery::ReturnPath.new(delivery).address, status: :delivered, forwarded_at: Time.current)
      get mailpiece_path(inbound_email.mailpiece)
    end

    assert_select "a[href=?]", mailpiece_path(delivery.mailpiece)
  end

  test "an html-only body is never rendered" do
    raw = <<~EOM
      Subject: Hi
      Content-Type: text/html

      <p><b>bold</b></p>
    EOM
    inbound_email = create_inbound_email(raw: raw)
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select "iframe", count: 0
    assert_no_match %r{bold}, response.body
  end

  test "a text body with an html alternative points at the html in the original source" do
    raw = Mail.new do
      subject "Hi"
      text_part { body "the text body" }
      html_part do
        content_type "text/html; charset=UTF-8"
        body "<p>the html body</p>"
      end
    end.to_s
    inbound_email = create_inbound_email(raw: raw)
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select "a[href=?][target=_blank]", mailpiece_original_path(inbound_email.mailpiece, format: :txt), text: "original source"
  end

  test "a text-only body carries no note about an html version" do
    inbound_email = create_inbound_email(raw: "Subject: Hi\r\n\r\nBody")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select "a", text: "original source", count: 0
  end

  test "a text-only body renders the sender's markup as literal text, never as live HTML" do
    inbound_email = create_inbound_email(raw: "Subject: Hi\r\n\r\n<b>bold</b> <a href=\"https://evil/\">click</a>")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_includes response.body, "&lt;b&gt;bold&lt;/b&gt;"
    assert_no_match %r{<b>bold</b>}, response.body
    assert_no_match %r{<a href="https://evil/">}, response.body
  end

  test "the JSON show renders an inbound-backed mailpiece with its direction and id" do
    get mailpiece_path(mailpieces(:received)), headers: api_token_env, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal "inbound", body["direction"]
    assert_equal mailpieces(:received).id, body["id"]
  end

  test "destroying an inbound-backed mailpiece removes the inbound email, its mailpiece, and redirects" do
    sign_in_as :leo

    assert_difference [ -> { InboundEmail.count }, -> { Mailpiece.count } ], -1 do
      delete mailpiece_path(mailpieces(:received))
    end

    assert_redirected_to root_path
    assert_equal "Mailpiece deleted", flash[:notice]
  end

  test "destroying a delivery-backed mailpiece removes the delivery, its mailpiece, and redirects" do
    sign_in_as :leo

    assert_difference [ -> { Delivery.count }, -> { Mailpiece.count } ], -1 do
      delete mailpiece_path(mailpieces(:queued))
    end

    assert_redirected_to root_path
    assert_equal "Mailpiece deleted", flash[:notice]
  end

  test "a member can neither delete a mailpiece nor see the button to" do
    sign_in_as :nonstaff

    get mailpiece_path(mailpieces(:queued))
    assert_select "form[action=?]", mailpiece_path(mailpieces(:queued)), count: 0

    assert_no_difference [ -> { Delivery.count }, -> { Mailpiece.count } ] do
      delete mailpiece_path(mailpieces(:queued))
    end

    assert_response :forbidden
  end

  test "an admin sees the button to delete a mailpiece" do
    sign_in_as :leo

    get mailpiece_path(mailpieces(:received))

    assert_select "form[action=?]", mailpiece_path(mailpieces(:received))
  end

  test "destroying a mailpiece over JSON succeeds with no content" do
    assert_difference [ -> { Delivery.count }, -> { Mailpiece.count } ], -1 do
      delete mailpiece_path(mailpieces(:queued)), headers: api_token_env, as: :json
    end

    assert_response :no_content
  end

  test "cannot view another account's mailpiece" do
    get mailpiece_path(mailpieces(:other_account)), headers: api_token_env, as: :json

    assert_response :not_found
  end

  test "cannot delete another account's mailpiece" do
    assert_no_difference [ -> { InboundEmail.count }, -> { Mailpiece.count } ] do
      delete mailpiece_path(mailpieces(:other_account)), headers: api_token_env, as: :json
    end

    assert_response :not_found
  end

  test "cannot list or view the mail of a domain you have no access to" do
    inbound_email = create_inbound_email(domain: domains(:private), rcpt_to: "secret@private.example")
    sign_in_as :nonstaff

    get search_path(q: "secret")
    assert_response :success
    assert_no_match "secret@private.example", response.body

    get mailpiece_path(inbound_email.mailpiece)
    assert_response :not_found
  end

  test "cannot delete the mail of a domain you have no access to" do
    inbound_email = create_inbound_email(domain: domains(:private), rcpt_to: "secret@private.example")
    users(:nonstaff).update!(role: :admin)
    sign_in_as :nonstaff

    assert_no_difference [ -> { InboundEmail.count }, -> { Mailpiece.count } ] do
      delete mailpiece_path(inbound_email.mailpiece)
    end

    assert_response :not_found
  end

  test "the creator of a private domain still reads its mail" do
    inbound_email = create_inbound_email(domain: domains(:private), rcpt_to: "secret@private.example")
    sign_in_as :leo

    get search_path(q: "secret")
    assert_response :success
    assert_includes response.body, "secret@private.example"

    get mailpiece_path(inbound_email.mailpiece)
    assert_response :success
  end

  test "an unauthenticated HTML request is redirected to sign in" do
    get mailpieces_path

    assert_response :redirect
  end

  test "a JSON request with an invalid bearer token is rejected" do
    get mailpieces_path, headers: bearer_token_env("not-a-real-token"), as: :json

    assert_response :unauthorized
  end

  test "the JSON show exposes the shared email content for an outbound mailpiece" do
    messages(:queued).update!(raw: file_fixture("raw.eml").read)

    get mailpiece_path(mailpieces(:queued)), headers: api_token_env, as: :json

    body = response.parsed_body
    assert_response :success
    assert_equal "Hello", body["subject"]
    assert_includes body["text"], "Hello there."
    assert body["raw_url"].present?
    assert_equal [], body["attachments"]
  end

  test "the JSON show lists an outbound mailpiece's attachments with a checksum" do
    raw = <<~EOM
      Subject: With attachment
      From: sender@example.com
      To: recipient@example.com
      Content-Type: multipart/mixed; boundary=MIX

      --MIX
      Content-Type: text/plain

      see attached
      --MIX
      Content-Type: text/plain; name="notes.txt"
      Content-Disposition: attachment; filename="notes.txt"

      hello notes
      --MIX--
    EOM
    delivery = create_delivery(raw: raw)
    delivery.message.extract_attachments

    get mailpiece_path(delivery.mailpiece), headers: api_token_env, as: :json

    assert_response :success
    attachment = response.parsed_body["attachments"].sole
    assert_equal "notes.txt", attachment["filename"]
    assert attachment["checksum"].present?
    assert attachment["url"].present?
  end

  test "the JSON show exposes an inbound mailpiece's auth results, original url, and parsed content" do
    inbound_emails(:received).update!(raw: file_fixture("raw.eml").read, spf: "pass", dkim: "pass", dmarc: "fail",
      arc_sealer: "lists.example.org", authentication_results: "mx.test; spf=pass smtp.mailfrom=a@example.com")

    get mailpiece_path(mailpieces(:received)), headers: api_token_env, as: :json

    body = response.parsed_body
    assert_response :success
    assert_equal "pass", body["spf"]
    assert_equal "fail", body["dmarc"]
    assert_equal "lists.example.org", body["arc_sealer"]
    assert_equal false, body["from_aligned"]
    assert_equal "mx.test; spf=pass smtp.mailfrom=a@example.com", body["authentication_results"]
    assert body["raw_url"].present?
    assert_equal "Hello", body["subject"]
    assert_includes body["text"], "Hello there."
  end

  test "the JSON show of an incinerated inbound mailpiece omits its body and lists no attachments" do
    inbound = create_inbound_email(status: :delivered)
    inbound.incinerate

    get mailpiece_path(inbound.mailpiece), headers: api_token_env, as: :json

    body = response.parsed_body
    assert_response :success
    assert_equal [], body["attachments"]
    assert_nil body["raw_url"]
    assert body["incinerated_at"].present?
  end

  test "the JSON show of an incinerated outbound mailpiece omits its body and lists no attachments" do
    delivery = create_delivery(status: :delivered)
    delivery.message.incinerate

    get mailpiece_path(delivery.mailpiece), headers: api_token_env, as: :json

    body = response.parsed_body
    assert_response :success
    assert_equal [], body["attachments"]
    assert_nil body["raw_url"]
    assert body["incinerated_at"].present?
  end
end
