class SubmissionRateLimiter
  def self.exceeded?(account)
    new(account).exceeded?
  end

  def initialize(account)
    @account = account
  end

  def exceeded?
    count = Rails.cache.increment(key, 1, expires_in: 1.minute)
    count.present? && count > Relay.submission_rate_limit
  end

  private
    def key
      "submission_rate_limit:#{@account.id}"
    end
end
