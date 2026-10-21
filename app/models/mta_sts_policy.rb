class MtaStsPolicy < ApplicationRecord
  PURGE_EXPIRED_AFTER = 7.days

  serialize :mx, type: Array, coder: JSON

  class << self
    # Side-effect: creates/renews the cached policy row.
    def lookup(domain)
      domain = MtaSts::Policy.normalize(domain)
      result = MtaSts.lookup(domain, known: remembered(domain), fetcher: fetcher)
      remember(domain, result.policy) if result.policy
      result
    end

    def refresh_all
      find_each do |record|
        lookup(record.domain)
      rescue StandardError
        # One broken domain must not halt the sweep
      end
    end

    def purge_expired
      where(expires_at: ...PURGE_EXPIRED_AFTER.ago).delete_all
    end

    private
      def fetcher
        MtaSts::Fetcher.new(permitted: ->(address) { !Surfguard.blocked_address?(address) })
      end

      def remembered(domain)
        find_by(domain: domain)&.to_policy
      end

      def remember(domain, policy)
        attributes = attributes_for(policy)

        create_with(attributes).create_or_find_by(domain: domain).update!(attributes)
      end

      def attributes_for(policy)
        { policy_id: policy.id, mode: policy.mode, mx: policy.mx,
          max_age: policy.max_age, fetched_at: policy.fetched_at, expires_at: policy.expires_at }
      end
  end

  def to_policy
    MtaSts::Policy.new(mode: mode, mx: mx, max_age: max_age, id: policy_id, domain: domain, fetched_at: fetched_at)
  rescue MtaSts::Policy::Invalid
    nil
  end
end
