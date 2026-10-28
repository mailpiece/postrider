module Delivery::Pacing
  extend ActiveSupport::Concern

  BULK_GAPS = { "outlook" => 30.seconds, "yahoo" => 30.seconds }.freeze

  def pace
    provider = mail_provider(destination_hosts.first)
    Delivery::DeliverJob.set(wait_until: PacingSlot.reserve(provider, BULK_GAPS.fetch(provider, 2.seconds))).perform_later(self)
  rescue DnsResolver::TransientError
    Delivery::DeliverJob.perform_later(self)
  end

  private
    def paced?
      domain.bulk? && !relaying? && !recipient_suppressed?
    end
end
