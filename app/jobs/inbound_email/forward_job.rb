class InboundEmail::ForwardJob < ApplicationJob
  queue_as :forwarding

  retry_on ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 5 do |job, _error|
    job.arguments.first.fail_permanently(reason: "forwarding_failed")
  end

  discard_on ActiveJob::DeserializationError

  def perform(inbound_email, ip:, helo:)
    inbound_email.forward(ip:, helo:)
  end
end
