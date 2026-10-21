module SendingToken::Refusable
  extend ActiveSupport::Concern

  MAX_REFUSALS_RECORDED_PER_HOUR = 10

  def refuse(ip)
    if address = native_address(ip)
      if first_refusal_within_the_hour?(address) && within_hourly_ceiling?
        track_domain_event "refused", ip: address.to_s
      end
    end
  end

  private
    # `.native` so ::ffff:203.0.113.9 counts as 203.0.113.9.
    def native_address(ip)
      IPAddr.new(ip.to_s).native
    rescue IPAddr::Error
      nil
    end

    def first_refusal_within_the_hour?(address)
      count = Rails.cache.increment(refusal_key(address), 1, expires_in: 1.hour)
      count == 1
    end

    # One IPv6 client holds a whole /64, so it counts as one address.
    def refusal_key(address)
      "sending_token_refusal:#{id}:#{address.ipv6? ? address.mask(64) : address}"
    end

    def within_hourly_ceiling?
      count = Rails.cache.increment("sending_token_refusals:#{id}", 1, expires_in: 1.hour)
      count.present? && count <= MAX_REFUSALS_RECORDED_PER_HOUR
    end
end
