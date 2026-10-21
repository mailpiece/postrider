require "mail"

class Mailpiece::Content
  def initialize(postable)
    @postable = postable
    @mail = Mail.new(postable.raw)
    @mail.all_parts
  rescue StandardError, SystemStackError
    @mail = nil
  end

  def parsed?
    @mail.present?
  end

  def to_h
    if @mail
      compact addresses.merge(metadata).merge(bodies)
    else
      { from: @postable.mail_from }
    end
  end

  private
    def addresses
      {
        from: @mail[:from]&.decoded || @postable.mail_from,
        to: @mail[:to]&.formatted,
        cc: @mail[:cc]&.formatted,
        bcc: @mail[:bcc]&.formatted,
        reply_to: @mail[:reply_to]&.formatted
      }
    end

    def metadata
      {
        subject: @mail.subject,
        in_reply_to: @mail[:in_reply_to]&.decoded,
        message_id: @mail[:message_id]&.decoded,
        headers: header_lines(@mail.header)
      }
    end

    def bodies
      { html: html_body, text: text_body }
    end

    def html_body
      if @mail.multipart?
        scrub @mail.html_part&.decoded
      elsif @mail.mime_type == "text/html"
        scrub @mail.decoded
      end
    end

    def text_body
      if @mail.multipart?
        scrub @mail.text_part&.decoded
      elsif @mail.mime_type.nil? || @mail.mime_type == "text/plain"
        scrub @mail.decoded
      end
    end

    def header_lines(header)
      header.fields.map { |field| "#{field.name}: #{field.value}" }
    end

    def scrub(string)
      string&.dup&.force_encoding(Encoding::UTF_8)&.scrub
    end

    def compact(hash)
      hash.reject { |_, value| value.blank? }
    end
end
