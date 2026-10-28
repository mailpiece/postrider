module Delivery::Pacing
  extend ActiveSupport::Concern

  def pace
    provider = mail_provider(destination_hosts.first)
    Delivery::DeliverJob.set(wait_until: PacingSlot.reserve(provider, 1.hour.to_f / Relay.bulk_messages_per_hour(provider))).perform_later(self)
  rescue DnsResolver::TransientError
    Delivery::DeliverJob.perform_later(self)
  end

  private
    def paced?
      domain.bulk? && !relaying? && !recipient_suppressed?
    end
end
