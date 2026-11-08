# Trace headers prepended to raw bytes (bytes only). Prepend is DKIM-safe (headers signed bottom-up).
# Any X-Spam- field the sender wrote is taken out, so every one the recipient reads is ours.
class InboundEmail::Headers
  SPAM_FIELD = /\AX-Spam-/i

  def initialize(inbound_email)
    @inbound_email = inbound_email
  end

  def prepended_to(raw)
    if raw
      header_block + MailGate::HeaderSection.new(raw).without(SPAM_FIELD)
    end
  end

  def lines
    fields.compact_blank.map { |name, value| "#{name}: #{sanitize(value)}" }
  end

  private
    def header_block
      lines.map { |line| "#{line}\r\n" }.join
    end

    # Every copy we hand on carries the scorer's verdict, and the receiving app decides.
    def fields
      if spam_check = @inbound_email.spam_check
        spam_check.headers.to_h.select { |name, _| name.match?(SPAM_FIELD) }
      else
        {}
      end
    end

    # A linebreak in a value would end the field and start another of the recipient's choosing.
    def sanitize(value)
      value.to_s.gsub(/[\r\n]+/, " ").strip
    end
end
