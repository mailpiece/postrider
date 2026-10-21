# Permanent bounce clears confirmation; owner must re-confirm the destination.
module Mailbox::Suspending
  extend ActiveSupport::Concern

  class_methods do
    def suspend_forwarding_to(domain, address)
      domain.mailboxes.forwarding.where(forward_to: address.to_s.strip.downcase).each(&:suspend_forwarding)
    end
  end

  def suspend_forwarding
    update! forward_confirmed_at: nil
  end
end
