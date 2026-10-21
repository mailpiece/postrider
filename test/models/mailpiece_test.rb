require "test_helper"

class MailpieceTest < ActiveSupport::TestCase
  test "creating an inbound email creates exactly one mailpiece scoped to the same account" do
    inbound_email = nil

    assert_difference -> { Mailpiece.count }, 1 do
      inbound_email = InboundEmail.create!(domain: domains(:example), mail_from: "a@example.com", rcpt_to: "b@example.com", raw: "Subject: hi\r\n\r\nBody")
    end

    mailpiece = inbound_email.mailpiece
    assert_equal inbound_email, mailpiece.postable
    assert_equal Current.account, mailpiece.account
    assert mailpiece.inbound_email?
    assert_not mailpiece.delivery?
    assert_equal inbound_email, mailpiece.inbound_email
  end

  test "creating a delivery creates exactly one mailpiece scoped to the same account" do
    delivery = nil

    assert_difference -> { Mailpiece.count }, 1 do
      delivery = messages(:queued).deliveries.create!(rcpt_to: "another@example.com")
    end

    mailpiece = delivery.mailpiece
    assert_equal delivery, mailpiece.postable
    assert_equal Current.account, mailpiece.account
    assert mailpiece.delivery?
    assert_not mailpiece.inbound_email?
    assert_equal delivery, mailpiece.delivery
  end

  test "inbound and outbound scopes select the right rows" do
    assert_includes Mailpiece.inbound, mailpieces(:received)
    assert_not_includes Mailpiece.inbound, mailpieces(:queued)

    assert_includes Mailpiece.outbound, mailpieces(:queued)
    assert_not_includes Mailpiece.outbound, mailpieces(:received)
  end

  test "the state screens' scopes list every mailpiece, each exactly once" do
    InboundEmail.statuses.each_key { |status| create_inbound_email(status: status) }
    Delivery.statuses.each_key { |status| create_delivery(status: status) }

    listed = %i[ delivered held deferred queued failed withheld discarded ].flat_map { |state| Mailpiece.public_send(state).ids }

    assert_equal Mailpiece.ids.sort, listed.sort
  end

  test "subject delegates to the postable" do
    assert_equal inbound_emails(:received).subject, mailpieces(:received).subject
    assert_equal "Hello", mailpieces(:received).subject
  end

  test "destroying an inbound email destroys its mailpiece" do
    mailpiece = mailpieces(:received)

    assert_difference -> { Mailpiece.count }, -1 do
      inbound_emails(:received).destroy
    end

    assert_not Mailpiece.exists?(mailpiece.id)
  end

  test "destroying a delivery destroys its mailpiece" do
    mailpiece = mailpieces(:queued)

    assert_difference -> { Mailpiece.count }, -1 do
      deliveries(:queued).destroy
    end

    assert_not Mailpiece.exists?(mailpiece.id)
  end

  test "destroying a message purges the mailpieces of its bulk-deleted deliveries" do
    mailpieces = [ mailpieces(:queued), messages(:queued).deliveries.create!(rcpt_to: "another@example.com").mailpiece ]

    assert_difference -> { Mailpiece.count }, -2 do
      messages(:queued).destroy
    end

    mailpieces.each { |mailpiece| assert_not Mailpiece.exists?(mailpiece.id) }
  end

  test "mailpieces are account-scoped" do
    assert_includes Current.account.mailpieces, mailpieces(:received)
    assert_not_includes Current.account.mailpieces, mailpieces(:other_account)
    assert_includes accounts(:other_account).mailpieces, mailpieces(:other_account)
  end
end
