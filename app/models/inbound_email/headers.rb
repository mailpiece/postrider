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

    # Every copy we hand on says what the spam check concluded, and the receiving app decides.
    def fields
      if spam_check = @inbound_email.spam_check
        spam_fields(spam_check)
      else
        {}
      end
    end

    def spam_fields(spam_check)
      score = format("%.1f", spam_check.score)

      {
        "X-Spam-Flag" => spam_check.flagged? ? "YES" : "NO",
        "X-Spam-Score" => score,
        "X-Spam-Level" => "*" * spam_check.score.floor.clamp(0, 50),
        "X-Spam-Status" => "#{spam_check.flagged? ? "Yes" : "No"}, score=#{score} tests=#{spam_check.symbol_names.join(",").presence || "none"}",
        "X-Spam-Action" => spam_action(spam_check)
      }
    end

    def spam_action(spam_check)
      if !spam_check.flagged?
        "accept"
      elsif spam_check.action == "reject"
        "reject"
      else
        "tag"
      end
    end

    # A linebreak in a value would end the field and start another of the recipient's choosing.
    def sanitize(value)
      value.to_s.gsub(/[\r\n]+/, " ").strip
    end
end
