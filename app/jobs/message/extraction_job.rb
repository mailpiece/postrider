class Message::ExtractionJob < ApplicationJob
  queue_as :forwarding

  discard_on ActiveJob::DeserializationError

  def perform(message)
    message.extract_attachments
  end
end
