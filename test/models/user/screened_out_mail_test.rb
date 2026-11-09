require "test_helper"

class User::ScreenedOutMailTest < ActiveSupport::TestCase
  test "screened_out_mail is the held mail from denied senders only" do
    create_inbound_email(status: :delivered, contact: contacts(:denied))
    create_inbound_email(status: :held, contact: contacts(:pending))

    assert_equal [ inbound_emails(:held) ], users(:leo).screened_out_mail.to_a
  end

  test "erase_screened_out_mail_later erases in the background" do
    assert_enqueued_with job: User::EraseScreenedOutMailJob, args: [ users(:leo) ] do
      users(:leo).erase_screened_out_mail_later
    end
  end

  test "erase_screened_out_mail_now erases held mail from denied senders, with its events and stored mail" do
    held = create_inbound_email(status: :held, contact: contacts(:denied), raw: "Subject: Spam\r\n\r\nBody")
    held.track_event "held", rcpt_to: held.rcpt_to, reason: "denied_sender"
    attachment_id = held.raw_email.attachment.id
    forwarded = create_inbound_email(status: :delivered, contact: contacts(:denied))
    waiting = create_inbound_email(status: :held, contact: contacts(:pending))

    users(:leo).erase_screened_out_mail_now

    assert_not InboundEmail.exists?(held.id)
    assert_empty Mailpiece.where(postable: held)
    assert_empty Event.where(eventable: held)
    assert_not ActiveStorage::Attachment.exists?(attachment_id)
    assert InboundEmail.exists?(forwarded.id)
    assert InboundEmail.exists?(waiting.id)
    assert contacts(:denied).reload.denied?
  end

  test "erase_screened_out_mail_now leaves mail on a domain the user cannot reach" do
    theirs = create_inbound_email(domain: domains(:private), status: :held, contact: contacts(:private))
    reachable = inbound_emails(:held)

    users(:nonstaff).erase_screened_out_mail_now

    assert InboundEmail.exists?(theirs.id)
    assert_not InboundEmail.exists?(reachable.id)
  end
end
