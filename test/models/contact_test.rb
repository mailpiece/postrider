require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "for_sender creates a pending contact on first contact, capturing the display name" do
    contact = Contact.for_sender(domains(:example), "Jane@Remote.Example", name: "Jane")

    assert contact.pending?
    assert_equal "jane@remote.example", contact.email
    assert_equal "Jane", contact.name
    assert_equal accounts(:davids_account), contact.account
  end

  test "for_sender returns the existing contact without disturbing its decision or name" do
    assert_no_difference -> { Contact.count } do
      assert_equal contacts(:approved), Contact.for_sender(domains(:example), "Friend@Sender.Example", name: "Someone Else")
    end

    assert contacts(:approved).reload.approved?
    assert_equal "Friend", contacts(:approved).name
  end

  test "for_sender keeps a look-alike address as punycode and marks the contact" do
    contact = Contact.for_sender(domains(:example), "jacopo@basecаmp.com", name: "Jacopo")

    assert_equal "jacopo@xn--basecmp-6fg.com", contact.email
    assert contact.lookalike?
    assert_equal contact, Contact.for_sender(domains(:example), "jacopo@basecаmp.com")
  end

  test "a blank display name is kept as none" do
    assert_nil Contact.for_sender(domains(:example), "quiet@remote.example", name: " ").name
  end

  test "for_sender takes the direction override out of a display name" do
    contact = Contact.for_sender(domains(:example), "jacopo@basecamp.com", name: "Jacopo\u202Epmac")

    assert_not_includes contact.name, "\u202E"
  end

  test "for_sender files an address with invalid bytes rather than failing the forward" do
    contact = Contact.for_sender(domains(:example), "jane@remote\xFF.example", name: "Jane\xFF")

    assert contact.persisted?
    assert contact.email.valid_encoding?
    assert contact.name.valid_encoding?
  end

  test "for_sender leaves a plain address unmarked" do
    assert_not Contact.for_sender(domains(:example), "jacopo@basecamp.com").lookalike?
  end

  test "for_sender without an address is nobody to record" do
    assert_nil Contact.for_sender(domains(:example), nil)
    assert_nil Contact.for_sender(domains(:example), "")
  end

  test "approve records the decision and queues the retroactive forward of held mail" do
    assert_enqueued_with(job: Contact::ForwardHeldJob, args: [ contacts(:denied) ]) do
      contacts(:denied).approve
    end

    assert contacts(:denied).approved?
  end

  test "approve forwards the held mail of a pending contact" do
    assert_enqueued_with(job: Contact::ForwardHeldJob, args: [ contacts(:pending) ]) do
      assert_changes -> { contacts(:pending).reload.decision }, from: "pending", to: "approved" do
        contacts(:pending).approve
      end
    end
  end

  test "screen_in approves someone new, with nothing held to forward" do
    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      Contact.screen_in(domains(:example), "Michael@Someemail.Example")
    end

    assert domains(:example).contacts.find_by(email: "michael@someemail.example").approved?
  end

  test "screen_in approves a sender waiting in the Screener and forwards what they had held" do
    assert_enqueued_with(job: Contact::ForwardHeldJob, args: [ contacts(:pending) ]) do
      Contact.screen_in(domains(:example), "newcomer@sender.example")
    end

    assert contacts(:pending).reload.approved?
  end

  test "screen_in leaves someone screened out where they are" do
    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      Contact.screen_in(domains(:example), "stranger@sender.example")
    end

    assert contacts(:denied).reload.denied?
  end

  test "deny turns a pending contact away, its mail still held" do
    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      assert_changes -> { contacts(:pending).reload.decision }, from: "pending", to: "denied" do
        contacts(:pending).deny
      end
    end
  end

  test "deny_all denies every contact in the relation, and nobody else" do
    assert_changes -> { contacts(:pending).reload.decision }, from: "pending", to: "denied" do
      assert_no_changes -> { contacts(:approved).reload.decision } do
        Contact.pending.deny_all
      end
    end
  end

  test "alphabetically sorts by name, or by address when there is none" do
    contacts(:pending).update!(name: "aardvark")

    assert_equal %w[ newcomer@sender.example friend@sender.example stranger@sender.example ],
      domains(:example).contacts.alphabetically.pluck(:email)
  end

  test "new mail from a contact touches it" do
    assert_changes -> { contacts(:pending).reload.updated_at } do
      create_inbound_email(status: :held, contact: contacts(:pending))
    end
  end

  test "the newest held email speaks for a contact" do
    latest = create_inbound_email(status: :held, contact: contacts(:denied))
    create_inbound_email(status: :delivered, contact: contacts(:denied))

    assert_equal [ latest, inbound_emails(:held) ], contacts(:denied).held_inbound_emails.to_a
    assert_equal latest, contacts(:denied).newest_held_email
    assert_nil contacts(:approved).newest_held_email
  end

  test "a contact is flagged when the spam check flagged their newest held email" do
    assert_not contacts(:denied).flagged?
    assert_not contacts(:approved).flagged?

    inbound_emails(:held).track_event "scored", action: "no_action", score: -1.8, complete: true, symbols: []
    assert_not contacts(:denied).reload.flagged?

    create_inbound_email(status: :held, contact: contacts(:denied))
      .track_event "scored", action: "reject", score: 7.4, complete: true, symbols: []
    assert contacts(:denied).reload.flagged?
  end

  test "deny_flagged denies the flagged contacts in the relation, and nobody else" do
    inbound_emails(:held).update!(contact: contacts(:pending))
    inbound_emails(:held).track_event "scored", action: "reject", score: 7.4, complete: true, symbols: []
    bystander = domains(:example).contacts.create!(email: "quiet@sender.example", decision: :pending)
    create_inbound_email(status: :held, contact: bystander)

    domains(:example).contacts.pending.deny_flagged

    assert contacts(:pending).reload.denied?
    assert bystander.reload.pending?
    assert contacts(:approved).reload.approved?
  end

  test "deny records the decision and forwards nothing" do
    assert_no_enqueued_jobs only: Contact::ForwardHeldJob do
      contacts(:approved).deny
    end

    assert contacts(:approved).denied?
  end

  test "contacts are numbered sequentially per account, and the number is what the URL reads" do
    first = domains(:example).contacts.create!(email: "jane@remote.example")
    second = domains(:private).contacts.create!(email: "john@remote.example")

    assert_equal first.number + 1, second.number
    assert_equal second.number.to_s, second.to_param
  end

  test "an address is recorded once per domain, regardless of case" do
    assert_raises ActiveRecord::RecordInvalid do
      domains(:example).contacts.create!(email: "Friend@Sender.Example")
    end

    assert domains(:private).contacts.create!(email: "friend@sender.example").persisted?
  end
end
