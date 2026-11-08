class Mailbox::SendForwardConfirmationJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(mailbox)
    mailbox.send_forward_confirmation_now
  end
end
