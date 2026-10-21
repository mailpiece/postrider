class Message::Headers
  MAX = 50
  # Identity, auth-results/ARC (receiver verdicts), and List-Unsubscribe (composed separately).
  FORBIDDEN_NAMES = %w[
    arc-authentication-results arc-message-signature arc-seal authentication-results
    bcc cc content-transfer-encoding content-type date dkim-signature from in-reply-to
    list-unsubscribe list-unsubscribe-post message-id mime-version received received-spf
    references reply-to return-path sender subject to
  ].freeze

  def initialize(raw)
    @raw = raw
  end

  def error
    if @raw.is_a?(Hash)
      if normalized.size > MAX
        "has too many entries"
      else
        forbidden_or_invalid_name
      end
    else
      "must be an object"
    end
  end

  def each(&block)
    normalized.each(&block)
  end

  private
    def normalized
      @normalized ||= @raw.stringify_keys.transform_values(&:to_s)
    end

    def forbidden_or_invalid_name
      normalized.each_key do |name|
        if FORBIDDEN_NAMES.include?(name.downcase)
          return "cannot override #{name}"
        elsif name !~ /\A[a-zA-Z0-9-]+\z/
          return "#{name} is not a valid header name"
        end
      end
      nil
    end
end
