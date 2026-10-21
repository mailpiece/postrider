require "mail"

class ParsedEmail
  CID_SOURCE = /src=(?<quote>["'])cid:(?<cid>[^"']+)\k<quote>/i

  def initialize(raw)
    @source = raw.to_s
    @mail = Mail.new(@source)
    @mail.all_parts
  rescue StandardError, SystemStackError
    @mail = nil
  end

  def source
    scrub @source
  end

  def present?
    @mail.present?
  end

  def subject
    @mail&.subject
  end

  def message_id
    @mail && @mail[:message_id]&.decoded
  end

  def from_address
    from_field&.address
  end

  def from_name
    scrub from_field&.display_name
  end

  def text_body
    if @mail
      if @mail.multipart?
        scrub @mail.text_part&.decoded
      elsif @mail.mime_type.nil? || @mail.mime_type == "text/plain"
        scrub @mail.decoded
      end
    end
  end

  def html_only?
    @mail.present? && text_body.blank? && (@mail.multipart? ? @mail.html_part.present? : @mail.mime_type == "text/html")
  end

  def html_alternative?
    @mail.present? && text_body.present? && @mail.multipart? && @mail.html_part.present?
  end

  def bare_attachment?
    @mail && !@mail.multipart? && @mail.attachment?
  end

  # For matching words as they render: entities decoded, blocks kept apart, and the text
  # of tags no sanitizer knows (Office, VML) kept, which pruning would drop.
  def html_text
    if @mail && (source = extract_html_body)
      fragment = Loofah.html5_fragment(source)
      fragment.css("script, style").remove
      fragment.to_text(encode_special_chars: false)
    end
  end

  def stored_attachments
    if @mail
      attachment_parts.map { |part| Attachment.new(part, referenced_cids) }
    else
      []
    end
  end

  private
    # Mail raises on some malformed lists only when addresses are read.
    def from_field
      @mail && @mail[:from]&.addrs&.first
    rescue StandardError
      nil
    end

    # Bare-file attachments (e.g. Google's DMARC zip) — no multipart envelope to walk.
    def attachment_parts
      if @mail.multipart?
        @mail.all_parts.select(&:attachment?)
      elsif @mail.attachment?
        [ @mail ]
      else
        []
      end
    end

    def referenced_cids
      @referenced_cids ||= extract_html_body.to_s.scan(CID_SOURCE).map(&:last)
    end

    def extract_html_body
      if @mail.multipart?
        scrub @mail.html_part&.decoded
      elsif @mail.mime_type == "text/html"
        scrub @mail.decoded
      end
    end

    def scrub(string)
      string&.dup&.force_encoding(Encoding::UTF_8)&.scrub
    end
end
