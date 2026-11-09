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
    assert_select ".breadcrumbs strong", text: "Mailpieces"
    assert_select "input[placeholder=?]", "Filter mail…"
    pieces.each { |mailpiece| assert_select "li.row##{dom_id(mailpiece)}" }
    assert_select "##{dom_id mailpieces(:held)} .row__end .status", text: "Held"
    assert_select "##{dom_id discarded} .row__end .status", text: "Discarded"
  end

  test "the list keeps a failed delivery's reply code for its own page" do
    deliveries(:bounced).attempts.create!(code: "550", output: "550 5.1.1 no such user", mx_host: "mx.recipient.example")
    sign_in_as :nonstaff

    get mailpieces_path
    assert_select "##{dom_id mailpieces(:bounced)} .status", text: "Bounced"
    assert_select "##{dom_id mailpieces(:bounced)}", text: /550/, count: 0

    get mailpiece_path(mailpieces(:bounced))
    assert_select ".envelope__ink", text: /Bounced\s+550 5.1.1/
  end

  test "the status filter lists each status page, All mail current on the index" do
    sign_in_as :nonstaff

    get mailpieces_path

    assert_response :success
    assert_select ".filter-bar .status-filter__button", text: "Status…"
    assert_equal [ root_path, mailpieces_delivered_path, mailpieces_held_path, mailpieces_queued_path, mailpieces_deferred_path, mailpieces_failed_path, mailpieces_withheld_path, mailpieces_discarded_path ],
      css_select(".status-filter__list a").pluck("href")
    assert_equal [ "All mail", "Delivered", "Held", "Queued", "Deferred", "Failed", "Blocked", "Discarded" ], css_select(".status-filter__list a").map { |link| link.text.squish }
    assert_select ".status-filter__list a[aria-current=page]", count: 1, text: "All mail"
  end

  test "an outbound mailpiece's row leads with its recipient, then the sending address, the subject and the status" do
    sign_in_as :nonstaff
    delivered = mailpieces(:delivered)
    bounced = mailpieces(:bounced)

    get mailpieces_path
    assert_select "li.row##{dom_id delivered}" do
      assert_select "a", count: 1
      assert_select "> a.mailpiece__link[href=?] .avatar", mailpiece_path(delivered)
      assert_select "> a.mailpiece__link[href=?] .row__title", mailpiece_path(delivered)
      assert_select "> a.mailpiece__link[href=?] .row__end", mailpiece_path(delivered)
      assert_select ".mailpiece__party", text: /\ASent\s+To recipient@example.com\z/
      assert_select ".mailpiece__own", text: "sender@example.com"
      assert_select ".mailpiece__subject", text: "Hello"
      assert_select ".row__end .status.status--muted", text: "Delivered"
    end

    get mailpieces_failed_path
    assert_select "li##{dom_id bounced} .row__end .status.status--error", text: "Bounced"
  end

  test "an inbound mailpiece's row leads with its sender, by name when known, then the mailbox it wrote to" do
    sign_in_as :nonstaff
    received = mailpieces(:received)
    nameless = create_inbound_email(mail_from: "billing@vendor.example", rcpt_to: "inbox@example.com").mailpiece

    get mailpieces_path

    assert_select "##{dom_id received}" do
      assert_select ".avatar", text: "FR"
      assert_select ".mailpiece__party", text: /\AReceived\s+Friend\z/
      assert_select ".mailpiece__own", text: "friend@sender.example · inbox@example.com"
    end
    assert_select "##{dom_id nameless}" do
      assert_select ".mailpiece__party", text: /\AReceived\s+billing@vendor.example\z/
      assert_select ".mailpiece__own", text: "inbox@example.com"
    end
  end

  test "a row marks which way the mail went, for the eye and for a screen reader" do
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "##{dom_id mailpieces(:received)} .mailpiece__party" do
      assert_select ".icon--arrow-left"
      assert_select ".for-screen-reader", text: "Received"
    end
    assert_select "##{dom_id mailpieces(:delivered)} .mailpiece__party" do
      assert_select ".icon--arrow-right"
      assert_select ".for-screen-reader", text: "Sent"
    end
  end

  test "a listed mailpiece with no envelope sender says so" do
    inbound_email = create_inbound_email(mail_from: "", status: :delivered, forwarded_at: Time.current)
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "##{dom_id inbound_email.mailpiece} .mailpiece__party", text: /\AReceived\s+No sender\z/
  end

  test "held mail is told by its status word, while a good outcome stays quiet" do
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "##{dom_id mailpieces(:held)} .status.status--warning", text: "Held"
    assert_select "##{dom_id mailpieces(:delivered)} .status.status--muted", text: "Delivered"
    assert_select "##{dom_id mailpieces(:held)} .row__end time[data-reader-time-target=timeordate]"
  end

  test "inbound mail still in flight reads queued in the list, as the status filter files it" do
    pending = create_inbound_email
    processing = create_inbound_email(status: :processing)
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "##{dom_id pending.mailpiece} .status", text: "Queued"
    assert_select "##{dom_id processing.mailpiece} .status", text: "Queued"
  end

  test "withheld reads blocked and exhausted reads retries ran out, in the list, on the envelope and on the status page" do
    withheld = create_delivery(status: :withheld)
    exhausted = create_delivery(status: :exhausted)
    sign_in_as :nonstaff

    get mailpieces_path
    assert_select "##{dom_id withheld.mailpiece} .status", text: "Blocked"
    assert_select "##{dom_id exhausted.mailpiece} .status", text: "Retries ran out"

    get mailpiece_path(withheld.mailpiece)
    assert_select ".envelope__ink strong", text: "Blocked"

    get mailpieces_withheld_path
    assert_select ".breadcrumbs strong", text: "Blocked"
    assert_select ".status-filter__button", text: "Blocked"
    assert_select ".status-filter__list a[aria-current=page][href=?]", mailpieces_withheld_path, count: 1
  end

  test "index loads the rest of a long list on scroll" do
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
  end

  test "index with a verified domain but no mail says to send something from it" do
    sign_in_as :nonstaff
    Mailpiece.delete_all

    get mailpieces_path

    assert_response :success
    assert_select ".blank-slate", text: "No mail yet for example.com. Send something from it, or set up a mailbox."
    assert_select ".blank-slate a[href=?]", domain_path(domains(:example)), text: "example.com"
    assert_select ".blank-slate a[href=?]", new_domain_path, count: 0
    assert_select ".status-filter__list a", count: 8
  end

  test "index with an unverified domain and no mail says to publish its DNS records, before any verified one" do
    sign_in_as :nonstaff
    Mailpiece.delete_all
    domains(:unverified).accesses.grant_to [ users(:nonstaff) ]

    get mailpieces_path

    assert_select ".blank-slate", text: "No mail yet. Publish the DNS records of unverified.example and send something."
    assert_select ".blank-slate a[href=?]", domain_path(domains(:unverified)), text: "unverified.example"
  end

  test "index with no domain tells an admin what to do and offers to add one" do
    sign_in_as :leo
    users(:leo).accesses.delete_all

    get mailpieces_path

    assert_select ".blank-slate", text: /No mail yet\. Add a domain, publish its DNS records, then create a sending token or set up a mailbox\./
    assert_select ".blank-slate a[href=?]", new_domain_path, text: "Add a domain"
  end

  test "index with no domain tells a member to ask an admin, with no button" do
    sign_in_as :nonstaff
    users(:nonstaff).accesses.delete_all

    get mailpieces_path

    assert_select ".blank-slate", text: "No mail yet. Ask an admin to add a domain and give you access to it."
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
    assert_select ".blank-slate", text: /No mail yet/, count: 0
    assert_select "li##{dom_id mailpieces(:queued)}"
    assert_select ".status-filter__list a[href=?]", mailpieces_queued_path
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

  test "the HTML show names a bounce category next to the other event details" do
    delivery = deliveries(:bounced)
    delivery.track_event("bounced", rcpt_to: delivery.rcpt_to, smtp_output: "550 no such user", category: "invalid")

    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_response :success
    assert_includes response.body, "Bounced mail to recipient@example.com (invalid)."
    assert_includes response.body, "550 no such user"
  end

  test "an admin sees the phrase a delivery was withheld for" do
    delivery = deliveries(:queued)
    delivery.withhold("free money")

    sign_in_as :leo

    get mailpiece_path(delivery.mailpiece)

    assert_includes response.body, "Withheld mail to recipient@example.com because it contains the blocked phrase &quot;free money&quot;"

    get mailpiece_path(delivery.mailpiece), as: :json

    assert_equal "free money", response.parsed_body["events"].sole["particulars"]["phrase"]
  end

  test "a member sees that a delivery was withheld, but not the phrase or that one was the cause" do
    delivery = deliveries(:queued)
    delivery.withhold("s3cret phrase")

    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_includes response.body, "Withheld mail to recipient@example.com"
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
    assert_select "form[action=?]", mailpiece_path(mailpiece)
  end

  test "the HTML show tells a passing spam check in the history by its score alone" do
    inbound_email = create_inbound_email
    inbound_email.track_event "scored", action: "no_action", score: -1.8, complete: true, symbols: [
      [ "SPF_PASS", -0.2, "SPF passed", "example.com" ], [ "DKIM_PASS", -0.1, "DKIM signature valid", "example.com" ],
      [ "DMARC_PASS", -0.5, "DMARC passed", "example.com" ], [ "ARC_PASS", -1.0, "ARC chain valid" ],
      [ "DMARC_NONE", 0.0, "No DMARC record" ], [ "GREYLISTED", 0.0, nil, "pass" ] ]
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".trail__sentence", text: "Spam check: no action, score −1.8."
  end

  test "the HTML show puts an inbound mailpiece on an envelope" do
    inbound_email = create_inbound_email(raw: "Message-ID: <abc@remote.example>\r\nSubject: Invoice\r\n\r\nBody",
      mail_from: "jane@remote.example", remote_host: "mail.remote.example", remote_ip: "203.0.113.7",
      spf: "pass", dkim: "pass", dmarc: "pass", arc: "pass", arc_sealer: "google.com", from_aligned: true)
    inbound_email.track_event "scored", action: "no_action", score: -1.8, complete: true, symbols: []
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope" do
      assert_select ".envelope__return", text: /jane@remote.example\s+mail.remote.example\s+203.0.113.7/
      assert_select ".envelope__subject", text: "Invoice"
      assert_select ".envelope__recipient", text: inbound_email.rcpt_to
      assert_select ".envelope__verdict", text: "Authentication: Genuine"
      assert_equal [ "SPF DKIM", "DMARC ARC" ], css_select(".envelope__checks span").map(&:text)
      assert_select ".envelope__stamp-note", text: "via google.com"
      assert_select ".envelope__ink", text: /Spam check\s+−1.8\s+no action/
      assert_select ".envelope__ids", text: /· <abc@remote.example> · \d+ bytes/
    end
  end

  test "the HTML show stamps an unverified sender and says why mail is held" do
    inbound_email = inbound_emails(:held)
    inbound_email.update!(spf: "softfail", dmarc: "fail")
    inbound_email.track_event "held", rcpt_to: inbound_email.rcpt_to, reason: "unauthenticated_sender"
    inbound_email.track_event "scored", action: "reject", score: 9.4, complete: true, symbols: []
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope__status", text: "Held · nothing vouches for its From address"
    assert_select ".envelope__verdict", text: "Authentication: Not verified"
    assert_select ".envelope__stamp span", text: "SPF softfail"
    assert_select ".envelope__stamp span", text: "DMARC failed"
    assert_select ".envelope__ink", text: /Spam check\s+9.4\s+would reject/
    assert_select ".envelope__ink", text: /Held\s+not forwarded/
  end

  test "the envelope shows a subject as it is" do
    inbound_email = create_inbound_email(raw: "Subject: RE: Invoice\r\n\r\nBody")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)
    assert_select ".envelope__subject", text: "RE: Invoice"

    get mailpieces_queued_path
    assert_select "##{dom_id inbound_email.mailpiece} .mailpiece__subject", text: "RE: Invoice"
  end

  test "the HTML show stamps inbound mail no check was recorded for as not checked" do
    inbound_email = create_inbound_email
    inbound_email.discard
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope__stamp" do
      assert_select ".envelope__verdict", text: "Authentication: Not checked"
      assert_select ".envelope__stamp-note", text: "no checks recorded"
    end
  end

  test "a look-alike sender shows as punycode, flagged as phishing, on the envelope and in the list" do
    lookalike = create_inbound_email(mail_from: "receipts@str\u0456pe.com", status: :held)
    normal = create_inbound_email(mail_from: "receipts@stripe.com", status: :held)
    sign_in_as :nonstaff

    get mailpiece_path(lookalike.mailpiece)
    assert_select ".envelope__return strong", text: "Phishing? receipts@xn--strpe-p2e.com"
    assert_select ".envelope__phishing[title=?]", "Sent as receipts@str\u0456pe.com: its letters imitate another address, a common phishing trick"

    get mailpieces_path
    assert_select "##{dom_id lookalike.mailpiece} .mailpiece__party", text: /\AReceived\s+Phishing\? receipts@xn--strpe-p2e.com\z/
    assert_select "##{dom_id normal.mailpiece} .mailpiece__party", text: /\AReceived\s+receipts@stripe.com\z/

    get mailpiece_path(normal.mailpiece)
    assert_select ".envelope__phishing", count: 0
  end

  test "the HTML show stamps outbound mail as signed by its domain, or by the relay for a forward" do
    delivery = deliveries(:queued)
    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)
    assert_select ".envelope__verdict", text: "Authentication: Signed"
    assert_select ".envelope__stamp span", text: "DKIM"
    assert_select ".envelope__stamp-note", text: delivery.domain.name

    delivery.message.update!(raw: file_fixture("raw.eml").read, origin: :forwarded)

    get mailpiece_path(delivery.mailpiece)
    assert_select ".envelope__stamp span", text: "ARC"
  end

  test "the JSON show leaves out an inbound mailpiece's spam verdict" do
    inbound_email = create_inbound_email
    inbound_email.track_event "scored", action: "reject", score: 20.0, complete: true, symbols: []
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece, format: :json)

    assert_response :success
    assert_not_includes response.body, "reject"
  end

  test "the HTML show renders every authentication verdict an inbound mailpiece recorded" do
    inbound_email = create_inbound_email(raw: "From: Jane <jane@remote.example>\r\nSubject: Hi\r\n\r\nBody",
      spf: "fail", dkim: "pass", dmarc: "pass", dmarc_policy: "reject",
      arc: "pass", arc_sealer: "lists.example.org", from_aligned: true,
      authentication_results: "mx.test; dkim=pass header.d=remote.example")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".envelope__verdict", text: "Authentication: Genuine"
    assert_equal [ "SPF failed", "DKIM DMARC", "ARC", "p=reject" ], css_select(".envelope__checks span").map(&:text)
    assert_select ".envelope__stamp-note", text: "via lists.example.org"
    assert_select ".trail__sentence", count: 1, text: "Received."
  end

  test "the HTML show calls a sender genuine on a DMARC pass alone, as forwarding does" do
    inbound_email = create_inbound_email(dmarc: "pass", from_aligned: false)
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope__verdict", text: "Authentication: Genuine"
    assert_select ".envelope__checks span", text: "DMARC"
  end

  test "the HTML show does not state a seal that failed as a hop the mail took" do
    inbound_email = create_inbound_email(arc: "fail", arc_sealer: "lists.example.org", dmarc_policy: "none")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope__verdict", text: "Authentication: Not verified"
    assert_select ".envelope__stamp-note", text: "lists.example.org seal failed"
    assert_select ".envelope__checks span", text: "p=none"
    assert_select ".trail__sentence", count: 1, text: "Received."
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

  test "the HTML show says a sender isn't verified rather than leaving it blank" do
    inbound_email = create_inbound_email(spf: "pass", from_aligned: false)
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".envelope__verdict", text: "Authentication: Not verified"
    assert_select ".envelope__checks span", text: "SPF"
  end

  # "Held" beside a wall of passing checks reads as a contradiction until it says which gate failed.
  test "the HTML show says in plain words why a message is held" do
    inbound_email = inbound_emails(:held)
    inbound_email.update!(spf: "pass", dkim: "pass", dmarc: "pass", from_aligned: true)
    inbound_email.track_event "held", rcpt_to: inbound_email.rcpt_to, reason: "denied_sender"
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".trail__sentence", text: "Held because its sender was not approved."
  end

  test "the HTML show asks about a sender writing for the first time, over the envelope" do
    inbound_emails(:held).update!(contact: contacts(:pending))
    sign_in_as :leo

    get mailpiece_path(mailpieces(:held))

    assert_select ".screener-question + .envelope", count: 1
    assert_select ".screener-question", text: /Newcomer is writing for the first time\. Forward their mail\?\s+1 email held/
    assert_select ".screener-question form[action=?] button", contact_approval_path(contacts(:pending)), text: "Yes"

    inbound_emails(:held).update!(contact: contacts(:approved))
    get mailpiece_path(mailpieces(:held))

    assert_select ".screener-question", count: 0
  end

  test "the HTML show offers to screen a screened-out sender back in, over the envelope" do
    sign_in_as :leo

    get mailpiece_path(mailpieces(:held))

    assert_select ".screener-question + .envelope", count: 1
    assert_select ".screener-question", text: /stranger@sender\.example is screened out\. Their mail is held and isn't forwarded unless you screen them in\./
    assert_select ".screener-question form[action=?][data-turbo-confirm=?] button", contact_approval_path(contacts(:denied)),
      "Forward 1 held email from stranger@sender.example to forwarding@elsewhere.example?", text: "Screen them in"
  end

  test "the HTML show leaves the screening banner off mail that was forwarded before its sender was screened out" do
    forwarded = create_inbound_email(status: :delivered, forwarded_at: Time.current, contact: contacts(:denied))
    sign_in_as :leo

    get mailpiece_path(forwarded.mailpiece)

    assert_response :success
    assert_select ".screener-question", count: 0
  end

  test "the HTML show calls mail accepted, not forwarded, when forwarding was not on" do
    inbound_email = create_inbound_email(status: :delivered, forwarded_at: Time.current)
    inbound_email.track_event "received", rcpt_to: inbound_email.rcpt_to, remote_ip: "203.0.113.7"
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope__status", text: "Accepted · not forwarded"
    assert_select ".trail__sentence", text: "Accepted. Forwarding was not on for this address."
    assert_select ".trail__sentence", text: "Received from 203.0.113.7."

    get mailpieces_path
    assert_select "##{dom_id inbound_email.mailpiece} .status.status--muted", text: "Accepted"
  end

  test "the HTML show calls discarded mail discarded, since nothing is bounced to its sender" do
    inbound_email = create_inbound_email
    inbound_email.discard
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".envelope__ink", text: /Discarded/
  end

  test "the HTML show links a matched bounce to the delivery it bounced" do
    delivery = deliveries(:bounced)
    sign_in_as :nonstaff

    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      inbound_email = create_inbound_email(rcpt_to: Delivery::ReturnPath.new(delivery).address, status: :delivered, forwarded_at: Time.current)
      get mailpiece_path(inbound_email.mailpiece)
    end

    assert_select ".trail__sentence", text: "Matched to the delivery it bounced."
    assert_select ".trail__sentence a[href=?]", mailpiece_path(delivery.mailpiece)
  end

  test "the HTML show's history holds only the receipt when an inbound mailpiece recorded nothing else" do
    inbound_email = create_inbound_email

    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".trail__sentence", count: 1, text: "Received."
  end

  test "the HTML show names the sending host and the forwarding address in its history" do
    inbound_email = inbound_emails(:received)
    inbound_email.track_event "received", rcpt_to: inbound_email.rcpt_to, remote_host: "mail.sender.example", remote_ip: "203.0.113.7"
    inbound_email.track_event "forwarded", rcpt_to: inbound_email.rcpt_to, forward_to: "elsewhere@example.net"
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".trail__sentence", count: 2
    assert_select ".trail__entry:first-child .trail__sentence", text: "Forwarded to elsewhere@example.net."
    assert_select ".trail__entry:last-child .trail__sentence", text: "Received from mail.sender.example (203.0.113.7)."
    assert_select ".envelope__status", text: "Forwarded · to elsewhere@example.net"
  end

  test "the HTML show keeps an outbound mailpiece's attempts, tags and submission in view" do
    delivery = deliveries(:deferred)
    delivery.message.update!(raw: file_fixture("raw.eml").read, tags: [ "welcome" ])
    delivery.attempts.create!(code: "451", output: "451 try again later", mx_host: "mx.recipient.example")
    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_select ".trail__sentence", text: "Delivery attempt at mx.recipient.example."
    assert_select ".smtp-reply", text: /\A451\s+try again later\z/
    assert_select ".trail__entry:last-child .trail__sentence", text: "Submitted."
    assert_select ".envelope__status", text: /\AOutbound · 1st attempt · next retry/
    assert_select ".envelope__return span", text: "Tags: welcome"
    assert_select ".envelope__address", text: /MX mx.recipient.example/
    assert_select ".envelope__ink", text: /Deferred\s+451 · \d\d:\d\d/
  end

  test "the HTML show says a forward queued a delivery nobody submitted" do
    delivery = deliveries(:queued)
    delivery.message.update!(raw: file_fixture("raw.eml").read, origin: :forwarded)
    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_select ".trail__entry:last-child .trail__sentence", text: "Queued by a forward."
  end

  test "an html-only body is never rendered, only pointed at in the original source" do
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
    assert_select "a[href=?][target=_blank]", mailpiece_original_path(inbound_email.mailpiece, format: :txt), text: "View the original source"
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
    assert_select "p", text: /Showing the text version/
    assert_select "a[href=?][target=_blank]", mailpiece_original_path(inbound_email.mailpiece, format: :txt), text: "original source"
  end

  test "a text-only body carries no note about an html version" do
    inbound_email = create_inbound_email(raw: "Subject: Hi\r\n\r\nBody")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select "p", text: /Showing the text version/, count: 0
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
