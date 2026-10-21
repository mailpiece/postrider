class MailboxMailer < ApplicationMailer
  def forward_confirmation(mailbox:, token:)
    @mailbox = mailbox
    @token = token

    headers["Auto-Submitted"] = "auto-generated"

    mail from: email_address_with_name(mailbox.forward_confirmation_sender, "PostRider"),
      to: mailbox.forward_to, subject: "Confirm forwarding for #{mailbox.address}",
      message_id: "<#{SecureRandom.uuid}@#{mailbox.domain.name}>"
  end
end
