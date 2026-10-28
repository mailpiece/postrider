class Delivery::PaceJob < ApplicationJob
  queue_as :deliveries

  retry_on StandardError, attempts: 5 do |job, _error|
    Delivery::DeliverJob.perform_later(job.arguments.first)
  end

  discard_on ActiveJob::DeserializationError

  def perform(delivery)
    delivery.pace
  end
end
