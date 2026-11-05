class Delivery::DeliverJob < ApplicationJob
  queue_as :deliveries

  # Retried until the delivery's deadline rather than for a number of tries.
  rescue_from StandardError do |error|
    delivery = arguments.first

    if delivery.retry_expired?
      delivery.exhaust
    else
      retry_job wait_until: delivery.schedule_retry, error: error
    end
  end

  # After catch-all retry so a deleted-mid-flight delivery is discarded, not re-raised via arguments.first.
  discard_on ActiveJob::DeserializationError

  def perform(delivery)
    delivery.deliver
  end
end
