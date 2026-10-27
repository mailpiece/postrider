require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "for_sender creates a denied contact on first contact, capturing the display name" do
    contact = Contact.for_sender(domains(:example), "Jane@Remote.Example", name: "Jane")

    assert contact.denied?
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
