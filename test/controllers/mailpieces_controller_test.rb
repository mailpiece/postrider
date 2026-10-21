require "test_helper"

class MailpiecesControllerTest < ActionDispatch::IntegrationTest
  test "visiting root without an account slug redirects to the session menu" do
    sign_in_as :nonstaff

    get "/"

    assert_redirected_to "/session/menu"
  end

  test "the app opens on the delivered mail, in either direction, and nothing else" do
    sign_in_as :nonstaff
    others = [ mailpieces(:held), mailpieces(:queued), mailpieces(:bounced), mailpieces(:deferred),
      create_inbound_email(status: :failed).mailpiece, create_inbound_email(status: :bounced).mailpiece, create_inbound_email.mailpiece ]

    get root_path

    assert_response :success
    assert_select ".breadcrumbs strong", text: "Mailpieces"
    [ mailpieces(:delivered), mailpieces(:received) ].each { |mailpiece| assert_select "li##{dom_id(mailpiece)}" }
    others.each { |mailpiece| assert_select "li##{dom_id(mailpiece)}", count: 0 }
    assert_select ".blank-slate", text: "No delivered mail.", count: 0
  end

  test "index counts the mail in each other state, over the list" do
    sign_in_as :nonstaff
    create_inbound_email(status: :failed)
    create_inbound_email(status: :bounced)
    create_inbound_email
    create_delivery(status: :withheld)
    deliver_from(domains(:private), status: "deferred")

    get mailpieces_path

    assert_response :success
    assert_equal [ mailpieces_held_path, mailpieces_failed_path, mailpieces_withheld_path, mailpieces_deferred_path, mailpieces_queued_path, mailpieces_discarded_path ],
      css_select(".rows--links a").pluck("href")
    assert_equal [ "Held", "Failed", "Withheld", "Deferred", "Queued", "Discarded" ], css_select(".rows--links a").map { |link| link.text.strip }
    assert_equal [ "1", "2", "1", "1", "2", "1" ], css_select(".rows--links .row__end").map { |count| count.text.strip }
    assert_select ".rows--links + .rows__section .rows__heading", text: "Delivered"
  end

  test "a row leads with its state, marked only when something went wrong" do
    sign_in_as :nonstaff
    delivered = mailpieces(:delivered)
    bounced = mailpieces(:bounced)

    get mailpieces_path
    assert_select "##{dom_id delivered} .row__meta", text: /\ADelivered · Sent · sender@example.com → recipient@example.com/
    assert_select "##{dom_id delivered} .row__meta .status", count: 0

    get mailpieces_failed_path
    assert_select "##{dom_id bounced} .row__meta", text: /\ABounced · Sent · sender@example.com → recipient@example.com/
    assert_select "##{dom_id bounced} .row__meta .status", text: "Bounced"
  end

  test "index loads the rest of a long list on scroll" do
    sign_in_as :nonstaff

    get mailpieces_path

    assert_select "[data-controller=pagination][data-pagination-paginate-on-intersection-value=true]"
  end

  test "index says so when no mail was recorded" do
    sign_in_as :nonstaff
    Mailpiece.delete_all

    get mailpieces_path

    assert_response :success
    assert_select ".blank-slate", text: "No mail recorded yet."
    assert_select ".rows--links a", count: 0
  end

  test "index says so when none of the mail was delivered" do
    sign_in_as :nonstaff
    Mailpiece.where.not(id: mailpieces(:queued).id).delete_all

    get mailpieces_path

    assert_response :success
    assert_select ".blank-slate", text: "No delivered mail."
    assert_select ".rows--links a[href=?]", mailpieces_queued_path
    assert_select ".rows--links a", count: 1
  end

  test "index as JSON lists the same mailpieces, leaving out a domain you cannot reach" do
    sign_in_as :nonstaff
    deliver_from(domains(:private), status: "delivered")

    get mailpieces_path, as: :json

    assert_response :success
    assert_equal [ mailpieces(:delivered), mailpieces(:received) ].map(&:id).sort, response.parsed_body.pluck("id").sort
  end

  test "the HTML show renders a delivery-backed mailpiece" do
    messages(:queued).raw = file_fixture("raw.eml").read
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
    assert_includes response.body, "Bounced mail to recipient@example.com (invalid)"
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

  test "the HTML show renders every authentication verdict an inbound mailpiece recorded" do
    inbound_email = create_inbound_email(raw: "From: Jane <jane@remote.example>\r\nSubject: Hi\r\n\r\nBody",
      spf: "fail", dkim: "pass", dmarc: "pass", dmarc_policy: "reject",
      arc: "pass", arc_sealer: "lists.example.org", from_aligned: true,
      authentication_results: "mx.test; dkim=pass header.d=remote.example")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".trail__sentence", text: "remote.example asks receivers to reject mail that fails DMARC"
    assert_select ".trail__sentence", text: "Passed through lists.example.org"
    assert_select ".trail__sentence", text: "The sender is genuine: SPF failed, DKIM, DMARC and ARC passed"
  end

  test "the HTML show calls a sender genuine on a DMARC pass alone, as forwarding does" do
    inbound_email = create_inbound_email(dmarc: "pass", from_aligned: false)
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".trail__sentence", text: "The sender is genuine: DMARC passed"
  end

  test "the HTML show does not state a seal that failed as a hop the mail took" do
    inbound_email = create_inbound_email(arc: "fail", arc_sealer: "lists.example.org", dmarc_policy: "none")
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".trail__sentence", text: "Carries a seal in the name of lists.example.org that did not verify"
    assert_select ".trail__sentence", text: "The From domain asks receivers to take no action on mail that fails DMARC"
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
    assert_select ".trail__sentence", text: "The sender is not verified: SPF passed"
  end

  # "Held" beside a wall of passing checks reads as a contradiction until it says which gate failed.
  test "the HTML show says in plain words why a message is held" do
    inbound_email = inbound_emails(:held)
    inbound_email.update!(spf: "pass", dkim: "pass", dmarc: "pass", from_aligned: true)
    inbound_email.track_event "held", rcpt_to: inbound_email.rcpt_to, reason: "denied_sender"
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".trail__sentence", text: "Held because this sender was not approved"
  end

  test "the HTML show calls mail accepted, not forwarded, when forwarding was not on" do
    inbound_email = create_inbound_email(status: :delivered, forwarded_at: Time.current)
    inbound_email.track_event "received", rcpt_to: inbound_email.rcpt_to, remote_ip: "203.0.113.7"
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".record .status", text: "Accepted"
    assert_select ".trail__sentence", text: "Accepted. Forwarding was not on for this address."
    assert_select ".trail__sentence", text: "Received from 203.0.113.7"

    get mailpieces_path
    assert_select "##{dom_id inbound_email.mailpiece} .row__meta", text: /Accepted/
  end

  test "the HTML show calls discarded mail discarded, since nothing is bounced to its sender" do
    inbound_email = create_inbound_email
    inbound_email.discard
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".record .status", text: "Discarded"
  end

  test "the HTML show links a matched bounce to the delivery it bounced" do
    delivery = deliveries(:bounced)
    sign_in_as :nonstaff

    with_env(RELAY_MAIL_DOMAIN: "relay.example") do
      inbound_email = create_inbound_email(rcpt_to: Delivery::ReturnPath.new(delivery).address, status: :delivered, forwarded_at: Time.current)
      get mailpiece_path(inbound_email.mailpiece)
    end

    assert_select ".trail__sentence", text: "Matched to the delivery it bounced"
    assert_select ".trail__sentence a[href=?]", mailpiece_path(delivery.mailpiece)
  end

  test "the HTML show's history holds only the receipt when an inbound mailpiece recorded nothing else" do
    inbound_email = create_inbound_email

    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_response :success
    assert_select ".trail__sentence", count: 1, text: "Received"
  end

  test "the HTML show names the sending host and the forwarding address in its history" do
    inbound_email = inbound_emails(:received)
    inbound_email.track_event "received", rcpt_to: inbound_email.rcpt_to, remote_host: "mail.sender.example", remote_ip: "203.0.113.7"
    inbound_email.track_event "forwarded", rcpt_to: inbound_email.rcpt_to, forward_to: "elsewhere@example.net"
    sign_in_as :nonstaff

    get mailpiece_path(inbound_email.mailpiece)

    assert_select ".trail__sentence", count: 2
    assert_select ".trail__entry:first-child .trail__sentence", text: "Forwarded to elsewhere@example.net"
    assert_select ".trail__entry:last-child .trail__sentence", text: "Received from mail.sender.example (203.0.113.7)"
    assert_select ".record .status", text: "Forwarded"
  end

  test "the HTML show keeps an outbound mailpiece's attempts, tags and submission in view" do
    delivery = deliveries(:deferred)
    delivery.message.update!(raw: file_fixture("raw.eml").read, tags: [ "welcome" ])
    delivery.attempts.create!(code: "451", output: "451 try again later", mx_host: "mx.recipient.example")
    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_select ".trail__sentence", text: "Delivery attempt at mx.recipient.example"
    assert_select ".smtp-reply", text: /451 try again later/
    assert_select ".trail__entry:last-child .trail__sentence", text: "Submitted"
    assert_select ".record__byline", text: /Next retry/
    assert_select ".record__byline", text: "Tags: welcome"
  end

  test "the HTML show says a forward queued a delivery nobody submitted" do
    delivery = deliveries(:queued)
    delivery.message.update!(raw: file_fixture("raw.eml").read, origin: :forwarded)
    sign_in_as :nonstaff

    get mailpiece_path(delivery.mailpiece)

    assert_select ".trail__entry:last-child .trail__sentence", text: "Queued by a forward"
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
    messages(:queued).raw = file_fixture("raw.eml").read

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
