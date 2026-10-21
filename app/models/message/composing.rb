module Message::Composing
  extend ActiveSupport::Concern

  class_methods do
    def compose_raw(from:, from_email:, to:, cc:, reply_to:, subject:, text:, html:, list_unsubscribe:,
      in_reply_to:, references:, headers:, attachments:)
      mail = Mail.new
      mail.from = from
      mail.to = to
      mail.cc = cc if cc.any?
      mail.reply_to = reply_to if reply_to.present?
      mail.subject = subject if subject.present?
      mail.message_id = "<#{SecureRandom.uuid}@#{from_email.split("@").last}>"
      unsubscribe = ListUnsubscribe.new(list_unsubscribe)
      if unsubscribe.present?
        mail["List-Unsubscribe"] = unsubscribe.to_s
        mail["List-Unsubscribe-Post"] = ListUnsubscribe::ONE_CLICK_POST if unsubscribe.one_click?
      end
      mail["In-Reply-To"] = in_reply_to if in_reply_to.present?
      mail["References"] = references if references.present?

      Message::Headers.new(headers).each do |name, value|
        mail[name] = value
      end

      if attachments.any?
        add_body_with_attachments(mail, text: text, html: html)
        attachments.each { |attachment| add_attachment(mail, attachment) }
      else
        add_body(mail, text: text, html: html)
      end

      mail.to_s
    end

    private
      def add_body(target, text:, html:)
        if text.present? && html.present?
          target.text_part = text_part(text)
          target.html_part = html_part(html)
        elsif html.present?
          target.content_type = "text/html; charset=UTF-8"
          target.body = html
        else
          target.content_type = "text/plain; charset=UTF-8"
          target.body = text
        end
      end

      def add_body_with_attachments(mail, text:, html:)
        if text.present? && html.present?
          mail.part content_type: "multipart/alternative" do |part|
            part.text_part = text_part(text)
            part.html_part = html_part(html)
          end
        elsif html.present?
          mail.add_part(html_part(html))
        else
          mail.add_part(text_part(text))
        end
      end

      def text_part(text)
        Mail::Part.new.tap do |part|
          part.content_type = "text/plain; charset=UTF-8"
          part.body = text
        end
      end

      def html_part(html)
        Mail::Part.new.tap do |part|
          part.content_type = "text/html; charset=UTF-8"
          part.body = html
        end
      end

      def add_attachment(mail, raw)
        attachment = Message::Attachment.wrap(raw)

        if attachment.cid.present?
          mail.attachments.inline[attachment.name] = { mime_type: attachment.content_type, content: attachment.decoded }
          mail.attachments[attachment.name].content_id = attachment.cid
        else
          mail.attachments[attachment.name] = { mime_type: attachment.content_type, content: attachment.decoded }
        end
      end
  end
end
