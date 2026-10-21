class InboundEmail::BounceCorrelationJob < ApplicationJob
  queue_as :forwarding

  retry_on ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 5 do |job, _error|
    job.arguments.first.fail_permanently(reason: "bounce_correlation_failed")
  end

  discard_on ActiveJob::DeserializationError

  def perform(inbound_email)
    inbound_email.correlate_bounce
  end
end
