module Delivery::Pacing
  extend ActiveSupport::Concern

  def pace
    provider = mail_provider(destination_hosts.first)
    gap = 1.day.to_f / Relay.bulk_messages_per_day(provider)

    Delivery::DeliverJob.set(wait_until: PacingSlot.reserve(provider, gap)).perform_later(self)
  rescue DnsResolver::TransientError
    Delivery::DeliverJob.perform_later(self)
  end

  private
    def paced?
      domain.bulk? && !relaying? && !recipient_suppressed?
    end
end
