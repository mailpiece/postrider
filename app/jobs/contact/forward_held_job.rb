class Contact::ForwardHeldJob < ApplicationJob
  queue_as :forwarding

  discard_on ActiveJob::DeserializationError

  def perform(contact)
    contact.forward_held_now
  end
end
