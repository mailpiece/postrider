class Delivery::DeliverJob < ApplicationJob
  queue_as :deliveries

  retry_on StandardError,
    attempts: Delivery::RETRY_SCHEDULE.size + 1,
    wait: ->(executions) { Delivery::RETRY_SCHEDULE[executions - 1] || Delivery::RETRY_SCHEDULE.last } do |job, _error|
    job.arguments.first.exhaust
  end

  # After catch-all retry so a deleted-mid-flight delivery is discarded, not re-raised via arguments.first.
  discard_on ActiveJob::DeserializationError

  def perform(delivery)
    delivery.deliver
  end
end
