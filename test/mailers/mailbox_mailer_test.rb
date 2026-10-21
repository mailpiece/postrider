require "test_helper"

class MailboxMailerTest < ActionMailer::TestCase
  test "forward_confirmation carries a slug-scoped confirmation link to the destination" do
    mailbox = mailboxes(:forwarding)
    token = mailbox.send(:generate_forward_confirmation_token)

    mail = MailboxMailer.forward_confirmation(mailbox: mailbox, token: token)

    assert_equal [ "noreply@example.com" ], mail.from
    assert_equal [ "forwarding@elsewhere.example" ], mail.to
    assert_equal "Confirm forwarding for forwarding@example.com", mail.subject
    assert_equal "auto-generated", mail["Auto-Submitted"].value

    link = Rails.application.routes.url_helpers.domain_mailbox_forwarding_confirmation_url(
      mailbox.domain, mailbox, script_name: mailbox.account.slug, forwarding_token: token)

    [ mail.text_part, mail.html_part ].each do |part|
      assert_includes part.body.to_s, link
      assert_includes part.body.to_s, mailbox.address
      assert_includes part.body.to_s, mailbox.forward_to
    end
  end
end
