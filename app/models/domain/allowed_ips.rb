module Domain::AllowedIps
  extend ActiveSupport::Concern

  MAX_ALLOWED_IPS = 10

  included do
    normalizes :allowed_ips, with: ->(value) {
      value.lines.map(&:strip).reject(&:blank?).uniq.join("\n").presence
    }

    validate :allowed_ips_within_limits, if: :allowed_ips_changed?

    after_update :track_allowed_ips_change, if: :saved_change_to_allowed_ips?
  end

  def allowed_ip_list
    allowed_ips.to_s.lines(chomp: true)
  end

  # `.native` so a client reached as ::ffff:203.0.113.9 matches 203.0.113.9.
  def allows_ip?(ip)
    allowed_ip_list.empty? || allowed_ip_list.any? { |range| IPAddr.new(range).include?(IPAddr.new(ip.to_s).native) }
  rescue IPAddr::Error
    false
  end

  private
    def allowed_ips_within_limits
      if allowed_ip_list.size > MAX_ALLOWED_IPS
        errors.add(:allowed_ips, "accepts at most #{MAX_ALLOWED_IPS} addresses or ranges")
      elsif invalid_line = allowed_ip_list.find { |line| !ipv4?(line) }
        errors.add(:allowed_ips, "can't hold \"#{invalid_line}\": only IPv4 addresses and ranges")
      end
    end

    def ipv4?(line)
      IPAddr.new(line).ipv4?
    rescue IPAddr::Error
      false
    end

    def track_allowed_ips_change
      track_event "allowed_ips_changed"
    end
end
