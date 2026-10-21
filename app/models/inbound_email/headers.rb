# Trace headers prepended to raw bytes (bytes only). Prepend is DKIM-safe (headers signed bottom-up).
class InboundEmail::Headers
  def initialize(inbound_email)
    @inbound_email = inbound_email
  end

  def prepended_to(raw)
    if raw
      header_block + raw
    end
  end

  private
    def header_block
      fields.compact_blank.map { |name, value| "#{name}: #{sanitize(value)}\r\n" }.join
    end

    # A linebreak in a value would end the field and start another of the recipient's choosing.
    def sanitize(value)
      value.to_s.gsub(/[\r\n]+/, " ").strip
    end
end
