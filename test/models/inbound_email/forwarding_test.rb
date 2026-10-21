require "test_helper"

class InboundEmail::ForwardingTest < ActiveSupport::TestCase
  FRIEND = "Friend <friend@sender.example>"
  JANE = "Jane <jane@remote.example>"

  setup do
    stub_env RELAY_HOSTNAME: "mx.example"
    DnsResolver.stubs(:name).returns(nil)
    publish_sealing_key
  end

  test "mail from an unknown, authenticated sender is held and its sender lands denied" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    email = inbound_to_mailbox(from: JANE)

    assert_no_difference -> { Message.count } do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.held?
    assert email.contact.denied?
    assert_equal "jane@remote.example", email.contact.email
    assert_equal "Jane", email.contact.name

    event = email.events.last
    assert_equal "inbound_email_held", event.action
    assert_equal "denied_sender", event.particulars["reason"]
  end

  test "mail from an unknown sender nothing vouches for is held under no contact" do
    email = inbound_to_mailbox(from: JANE)

    assert_no_difference [ -> { Message.count }, -> { Contact.count } ] do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.held?
    assert_nil email.contact
    assert_equal "unauthenticated_sender", email.events.last.particulars["reason"]
  end

  test "mail from an approved, authenticated sender is forwarded to the confirmed destination" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    email = inbound_to_mailbox

    assert_difference -> { Message.count }, 1 do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.delivered?
    assert email.forwarded?
    forward = Message.last
    assert_equal [ "forwarded" ], forward.tags
    assert_equal mailboxes(:forwarding).forward_to, forward.deliveries.sole.rcpt_to
    assert_includes forward.raw, "#{InboundEmail::Forwarding::TRACE_HEADER}: example.com\r\n",
      "the forward must carry a trace header ahead of the untouched original bytes"
    assert_includes forward.raw, "#{InboundEmail::Forwarding::TRACE_HEADER}-To: #{mailboxes(:forwarding).forward_to}\r\n" \
      "#{InboundEmail::Forwarding::TRACE_HEADER}-For: #{mailboxes(:forwarding).address} #{mailboxes(:forwarding).forward_to}\r\nFrom: Friend",
      "the forward must name where it went and the mailbox it came from"

    event = email.events.last
    assert_equal "inbound_email_forwarded", event.action
    assert_equal mailboxes(:forwarding).forward_to, event.particulars["forward_to"]
  end

  test "a forward carries an ARC set sealed with the relay's key, which verifies against the published record" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    inbound_to_mailbox.forward(ip: "203.0.113.1", helo: "sender.example")

    result = verify_arc(Message.last.raw)

    assert_equal "pass", result.status
    assert_equal 1, result.sets.sole.instance
    assert_equal "mx.example", result.sets.sole.seal.domain
  end

  test "the seal states what this hop concluded at receipt rather than a verdict reached later" do
    stub_verdicts(dmarc: "pass", from_aligned: true, authentication_results: "mx.example; dmarc=pass header.from=remote.example")
    inbound_to_mailbox.forward(ip: "203.0.113.1", helo: "sender.example")

    assert_includes Message.last.raw,
      "ARC-Authentication-Results: i=1; mx.example; dmarc=pass header.from=remote.example\r\n"
  end

  test "a chain that arrived broken is sealed cv=fail, and one that never existed cv=none" do
    stub_verdicts(dmarc: "pass", from_aligned: true, arc: "fail")
    inbound_to_mailbox.forward(ip: "203.0.113.1", helo: "sender.example")

    assert_includes Message.last.raw, "cv=fail"

    stub_verdicts(dmarc: "pass", from_aligned: true, arc: nil)
    inbound_to_mailbox(raw: raw_from(FRIEND).sub("Hi", "Hello")).forward(ip: "203.0.113.1", helo: "sender.example")

    assert_includes Message.last.raw, "cv=none"
  end

  test "mail received before authentication results were stored still seals with an authserv-id" do
    stub_verdicts(dmarc: "pass", from_aligned: true, authentication_results: nil)
    inbound_to_mailbox.forward(ip: "203.0.113.1", helo: "sender.example")

    assert_includes Message.last.raw, "ARC-Authentication-Results: i=1; mx.example;\r\n none\r\n"
  end

  test "a seal we cannot write never costs the forward" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    Relay::SealingKey.any_instance.stubs(:seal).raises(ArgumentError, "chain already carries 50 sets")

    assert_difference -> { Message.count }, 1 do
      inbound_to_mailbox.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert Message.last.raw.start_with?("#{InboundEmail::Forwarding::TRACE_HEADER}: example.com\r\n")
  end

  test "a spoofed approved From line is held, not forwarded, when the mail does not authenticate" do
    email = inbound_to_mailbox

    assert_no_difference -> { Message.count } do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.held?
    assert_nil email.contact, "a spoofed From must not land in the history of the contact it imitates"
    assert_equal "unauthenticated_sender", email.events.last.particulars["reason"]
  end

  test "mail from a denied sender is held under that decision" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    email = inbound_to_mailbox(from: contacts(:denied).email)

    assert_no_difference -> { Message.count } do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.held?
    assert_equal "denied_sender", email.events.last.particulars["reason"]
  end

  test "mail that already crossed this relay is never forwarded again" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    email = inbound_to_mailbox(raw: looping_raw)

    assert_no_difference -> { Message.count } do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.held?
    assert_equal "forwarding_loop", email.events.last.particulars["reason"]
  end

  test "a mailbox whose destination is unconfirmed keeps the ordinary webhook-only path" do
    mailboxes(:inbox).update!(forward_to: "dest@elsewhere.example")
    email = create_inbound_email(rcpt_to: mailboxes(:inbox).address, mail_from: "jane@remote.example", raw: raw_from(JANE))

    assert_no_difference [ -> { Message.count }, -> { Contact.count } ] do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end

    assert email.reload.delivered?
    assert_not email.forwarded?
  end

  test "approving a contact retroactively forwards their held mail" do
    inbound_emails(:held).update!(raw: file_fixture("raw.eml").read, dmarc: "pass")

    assert_difference -> { Message.count }, 1 do
      perform_enqueued_jobs only: Contact::ForwardHeldJob do
        contacts(:denied).approve
      end
    end

    assert inbound_emails(:held).reload.delivered?
    assert_equal mailboxes(:forwarding).forward_to, Message.last.deliveries.sole.rcpt_to
  end

  test "a receipt whose event fails leaves the mail to forward on the retry" do
    stub_verdicts(dmarc: "pass", from_aligned: true)
    email = inbound_to_mailbox
    Event.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_no_difference [ -> { Message.count }, -> { Event.count } ] do
      assert_raises(ActiveRecord::RecordInvalid) { email.forward(ip: "203.0.113.1", helo: "sender.example") }
    end
    assert email.reload.processing?

    Event.any_instance.unstub(:save!)

    assert_difference -> { Message.count }, 1 do
      email.forward(ip: "203.0.113.1", helo: "sender.example")
    end
    assert email.reload.delivered?
    assert_equal 1, email.events.where(action: "inbound_email_received").count
  end

  test "a forward whose event fails raises and leaves nothing behind" do
    email = inbound_emails(:held)
    email.update!(raw: file_fixture("raw.eml").read, dmarc: "pass")
    email.contact.update!(decision: :approved)
    Event.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid)

    assert_no_difference [ -> { Message.count }, -> { Delivery.count }, -> { Event.count } ] do
      assert_no_enqueued_jobs only: Delivery::DeliverJob do
        assert_raises(ActiveRecord::RecordInvalid) { email.forward_held }
      end
    end

    assert email.reload.held?
    assert_nil email.forwarded_at
  end

  test "held mail ages out on its own retention clock, apart from processed mail's" do
    old_held = inbound_emails(:held)
    old_held.update_column(:created_at, 91.days.ago)

    fresh_held = inbound_to_mailbox
    fresh_held.update!(status: :held)
    fresh_held.update_column(:created_at, 89.days.ago)

    old_delivered = inbound_emails(:received)
    old_delivered.update!(forwarded_at: 31.days.ago)

    due = InboundEmail.due_for_incineration
    assert_includes due, old_held
    assert_not_includes due, fresh_held
    assert_includes due, old_delivered
  end

  test "mail cannot be filed under a contact of another domain" do
    assert_raises ActiveRecord::RecordInvalid do
      inbound_emails(:held).update! contact: contacts(:private)
    end
  end

  private
    def inbound_to_mailbox(from: FRIEND, raw: raw_from(from))
      create_inbound_email(rcpt_to: mailboxes(:forwarding).address, mail_from: Mail::Address.new(from).address, raw: raw)
    end

    def raw_from(from)
      "From: #{from}\r\nSubject: Hi\r\n\r\nBody"
    end

    def looping_raw
      "#{InboundEmail::Forwarding::TRACE_HEADER}: elsewhere.example\r\n" + raw_from(FRIEND)
    end

    # Verified through the gem's own validator, against the record we tell operators to publish.
    def verify_arc(raw)
      resolver = mock("resolver")
      resolver.stubs(:txt).returns([ Relay::SealingKey.instance.txt_value ])
      MailAuth::Arc.verify(MailAuth::Message.new(raw), resolver: resolver)
    end

    # Drive the gate at the same seam production uses.
    def stub_verdicts(dmarc: "none", from_aligned: false, arc: "none", authentication_results: "mx.example; dmarc=#{dmarc}")
      InboundAuthentication.stubs(:verdicts).returns(
        spf: "none", dkim: "none", dmarc: dmarc, dmarc_policy: nil,
        arc: arc, arc_sealer: nil, from_aligned: from_aligned,
        authentication_results: authentication_results
      )
    end
end
