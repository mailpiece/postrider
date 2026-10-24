require "test_helper"

class MailboxTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "the reserved mailboxes cannot be destroyed" do
    Domain::RESERVED_LOCAL_PARTS.each do |local_part|
      mailbox = domains(:example).mailboxes.find_by!(local_part: local_part)

      assert mailbox.reserved?
      assert_not mailbox.destroy
      assert domains(:example).mailboxes.exists?(mailbox.id)
    end
  end

  test "an ordinary mailbox is not reserved and can be destroyed" do
    assert_not mailboxes(:inbox).reserved?
    assert mailboxes(:inbox).destroy
  end

  test "destroying a domain still clears its reserved mailboxes, guard notwithstanding" do
    mailbox_ids = domains(:unverified).mailboxes.ids
    assert domains(:unverified).mailboxes.any?(&:reserved?)

    assert domains(:unverified).destroy

    assert_empty Mailbox.where(id: mailbox_ids)
  end

  test "requires a local_part" do
    mailbox = domains(:example).mailboxes.build(local_part: "")

    assert_not mailbox.valid?
    assert_includes mailbox.errors[:local_part], "can't be blank"
  end

  test "local_part is unique within a domain" do
    duplicate = domains(:example).mailboxes.build(local_part: "inbox")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:local_part], "has already been taken"
  end

  test "the same local_part is fine on two different domains" do
    assert domains(:private).mailboxes.build(local_part: "inbox").valid?
  end

  test "normalizes local_part by stripping whitespace and downcasing" do
    mailbox = domains(:example).mailboxes.create!(local_part: "  Everyone  ")

    assert_equal "everyone", mailbox.local_part
  end

  test "rejects a local_part containing an internal space" do
    mailbox = domains(:example).mailboxes.build(local_part: "some mailbox")

    assert_not mailbox.valid?
    assert_includes mailbox.errors[:local_part], "is not a valid mailbox"
  end

  test "accepts common dot-atom local_part characters" do
    assert domains(:example).mailboxes.build(local_part: "sales+vip.team").valid?
  end

  test "a dot-variant is a distinct mailbox on the same domain" do
    assert domains(:example).mailboxes.build(local_part: "in.box").valid?
  end

  test "updating a mailbox does not collide with itself" do
    mailbox = mailboxes(:inbox)

    mailbox.local_part = "Inbox"

    assert mailbox.valid?
  end

  test "a mailbox takes its account from its domain" do
    mailbox = domains(:other_account).mailboxes.create!(local_part: "everyone")

    assert_equal accounts(:other_account), mailbox.account
  end

  test "forwarding requires both a destination and its confirmation" do
    mailbox = mailboxes(:inbox)
    assert_not mailbox.forwarding?

    mailbox.update! forward_to: "someone@example.com"
    assert_not mailbox.forwarding?

    mailbox.confirm_forwarding
    assert mailbox.forwarding?
    assert_includes domains(:example).mailboxes.forwarding, mailbox
  end

  test "changing the forwarding destination resets its confirmation" do
    mailbox = mailboxes(:forwarding)

    mailbox.update! forward_to: "elsewhere@example.com"

    assert_nil mailbox.forward_confirmed_at
    assert_not mailbox.forwarding?
  end

  test "normalizes forward_to and treats blank as off" do
    mailbox = mailboxes(:inbox)

    mailbox.update! forward_to: "  Someone@Example.COM  "
    assert_equal "someone@example.com", mailbox.forward_to

    mailbox.update! forward_to: "   "
    assert_nil mailbox.forward_to
  end

  test "the emailed token confirms forwarding, and nothing else does" do
    mailbox = mailboxes(:unconfirmed_forwarding)
    token = forward_confirmation_token_for(mailbox)

    assert_not mailbox.confirm_forwarding_using_token("nonsense")
    assert mailbox.confirm_forwarding_using_token(token)
    assert mailbox.forwarding?
  end

  test "a token expires after 24 hours" do
    mailbox = mailboxes(:unconfirmed_forwarding)
    token = forward_confirmation_token_for(mailbox)

    travel_to 25.hours.from_now do
      assert_not mailbox.confirm_forwarding_using_token(token)
      assert_not mailbox.reload.forwarding?
    end
  end

  test "a token confirms only the mailbox it was issued for" do
    mailbox = mailboxes(:unconfirmed_forwarding)
    other = domains(:example).mailboxes.create!(local_part: "other", forward_to: "someone@example.com")

    assert_not other.confirm_forwarding_using_token(forward_confirmation_token_for(mailbox))
    assert_not other.forwarding?
  end

  test "a token stops working once the destination changes" do
    mailbox = mailboxes(:forwarding)
    token = forward_confirmation_token_for(mailbox)

    mailbox.update! forward_to: "elsewhere@example.com"

    assert_not mailbox.confirm_forwarding_using_token(token)
    assert_not mailbox.forwarding?
  end

  test "send forward confirmation from the domain with a null sender, out of the mail log" do
    mailboxes(:unconfirmed_forwarding).send_forward_confirmation

    message = domains(:example).messages.system.sole
    assert_equal "noreply@example.com", message.mail_from
    assert_equal "", message.envelope_from
    assert_includes message.raw, "Subject: Confirm forwarding for unconfirmed@example.com"
    assert_equal [ "unconfirmed@elsewhere.example" ], message.deliveries.pluck(:rcpt_to)
    assert_nil message.deliveries.sole.mailpiece
  end

  test "send forward confirmation needs a destination that is not suppressed, a verified domain and an active account" do
    unverified = domains(:unverified).mailboxes.create!(local_part: "fwd", forward_to: "someone@elsewhere.example")
    mailbox = mailboxes(:unconfirmed_forwarding)
    domains(:example).suppressions.create!(address: mailbox.forward_to)

    assert_no_difference -> { Message.count } do
      mailboxes(:inbox).send_forward_confirmation
      unverified.send_forward_confirmation
      mailbox.send_forward_confirmation
    end

    domains(:example).suppressions.delete_all
    mailbox.account.create_cancellation!(initiated_by: users(:leo))

    assert_no_difference -> { Message.count } do
      mailbox.send_forward_confirmation
    end
  end

  test "a forward is not confirmable while its domain's sending is off" do
    domains(:example).update!(sending: false)

    assert_not mailboxes(:unconfirmed_forwarding).forward_confirmable?
  end

  test "a confirmation is sent only on the save that changes the destination" do
    mailbox = mailboxes(:inbox)

    assert_enqueued_with job: Mailbox::SendForwardConfirmationJob, args: [ mailbox ] do
      mailbox.update!(forward_to: "someone@example.com")
    end
    assert mailbox.should_send_forward_confirmation?

    assert_no_enqueued_jobs only: Mailbox::SendForwardConfirmationJob do
      mailbox.update!(forward_to: "someone@example.com")
      mailbox.update!(forward_to: nil)
    end
  end

  test "a destination has to be an email address, and not this mailbox itself" do
    mailbox = mailboxes(:inbox)

    mailbox.forward_to = "not-an-address"
    assert_not mailbox.valid?
    assert_includes mailbox.errors.attribute_names, :forward_to

    mailbox.forward_to = mailbox.address
    assert_not mailbox.valid?
    assert_includes mailbox.errors.attribute_names, :forward_to

    mailbox.forward_to = "someone@example.com"
    assert mailbox.valid?
  end

  private
    def forward_confirmation_token_for(mailbox)
      mailbox.send(:generate_forward_confirmation_token)
    end
end
