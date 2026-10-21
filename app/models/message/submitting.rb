module Message::Submitting
  extend ActiveSupport::Concern

  MAX_ATTACHMENTS = 20
  MAX_RECIPIENTS = 50
  MAX_TAGS = 10
  MAX_METADATA = 10
  MAX_METADATA_VALUE_LENGTH = 1000

  # On the model, not just in submit: submit_raw takes tags straight from the
  # submitter's X-PostRider-Tags header.
  included do
    validate :tags_within_limit
  end

  class_methods do
    def submit(domain:, from:, from_name: nil, to:, cc: [], bcc: [], reply_to: nil, reply_to_name: nil,
      envelope_from: nil, return_path: nil, subject: nil, text: nil, html: nil, list_unsubscribe: nil,
      in_reply_to: nil, references: nil, tags: [], metadata: {}, headers: {}, attachments: [])
      recipients = recipient_addresses(to) + recipient_addresses(cc) + recipient_addresses(bcc)
      from_email = EmailAddress.extract(from)
      message = new(domain: domain, mail_from: from_email, tags: tags, metadata: metadata)

      if from_email.blank?
        message.errors.add(:from, "must be a valid email address")
      elsif recipients.empty?
        message.errors.add(:base, "needs at least one recipient in to, cc, or bcc")
      elsif recipients.size > MAX_RECIPIENTS
        message.errors.add(:base, "accepts at most #{MAX_RECIPIENTS} recipients across to, cc, and bcc")
      elsif text.blank? && html.blank?
        message.errors.add(:base, "needs a text or html")
      elsif (attachment_error = invalid_attachment_error(attachments))
        message.errors.add(:attachments, attachment_error)
      elsif (header_error = invalid_headers_error(headers))
        message.errors.add(:headers, header_error)
      elsif (envelope_error = invalid_envelope_from_error(envelope_sender_for(envelope_from:, return_path:)))
        message.errors.add(:envelope_from, envelope_error)
      elsif (tag_error = invalid_tags_error(tags))
        message.errors.add(:tags, tag_error)
      elsif (metadata_error = invalid_metadata_error(metadata))
        message.errors.add(:metadata, metadata_error)
      else
        message.envelope_from = envelope_return_path(envelope_from, return_path)
        message.raw = compose_raw(
          from: EmailAddress.format(from, name: from_name),
          from_email: from_email,
          to: EmailAddress.format_list(to),
          cc: EmailAddress.format_list(cc),
          reply_to: EmailAddress.format(reply_to, name: reply_to_name),
          subject: subject, text: text, html: html, list_unsubscribe: list_unsubscribe,
          in_reply_to: in_reply_to, references: references,
          headers: headers, attachments: attachments
        )
        # Read before the transaction opens, so the parse never holds the write lock.
        phrase = message.blocked_phrase

        # Transaction so a raised submit leaves no message (idempotency relies on it).
        transaction do
          message.deliver_to(recipients, withholding: phrase) if message.save
        end
      end

      message
    end

    def submit_raw(domain:, mail_from:, raw:, tags:, recipients:, origin: :submitted, envelope_from: nil)
      message = new(domain:, mail_from:, raw:, tags:, origin:, envelope_from:)
      phrase = message.blocked_phrase

      transaction do
        message.save!
        message.deliver_to(recipients, withholding: phrase)
        message
      end
    end

    def envelope_sender_for(envelope_from:, return_path:)
      envelope_from.nil? ? return_path : envelope_from
    end

    private
      def recipient_addresses(values)
        EmailAddress.extract_list(values)
      end

      def invalid_attachment_error(attachments)
        return "are invalid" unless attachments.is_a?(Array)
        return "are invalid" if attachments.size > MAX_ATTACHMENTS

        decoded_bytes = 0

        attachments.lazy.filter_map do |raw|
          if attachment = Message::Attachment.wrap(raw)
            attachment.error || ("are invalid" if (decoded_bytes += attachment.decoded.bytesize) > Relay.max_outbound_message_size)
          else
            "are invalid"
          end
        end.first
      end

      def invalid_headers_error(headers)
        Message::Headers.new(headers).error
      end

      def invalid_envelope_from_error(value)
        if value.present? && EmailAddress.extract(value).blank?
          "must be a valid email address"
        end
      end

      def invalid_tags_error(tags)
        "are invalid" unless Array(tags).all?(String)
      end

      def invalid_metadata_error(metadata)
        if !metadata.is_a?(Hash)
          "must be an object"
        elsif metadata.size > MAX_METADATA
          "accepts at most #{MAX_METADATA} entries"
        elsif metadata.any? { |_, value| value.to_s.length > MAX_METADATA_VALUE_LENGTH }
          "values must be #{MAX_METADATA_VALUE_LENGTH} characters or fewer"
        end
      end

      def envelope_return_path(envelope_from, return_path)
        if envelope_from == ""
          ""
        else
          EmailAddress.extract(envelope_sender_for(envelope_from:, return_path:))
        end
      end
  end

  # A forward carries a third party's words, and a check that breaks must not cost anyone their mail.
  def blocked_phrase
    if submitted? && domain.blocked_phrases?
      if parsed_email.bare_attachment?
        domain.blocked_phrase_in(parsed_email.subject)
      else
        domain.blocked_phrase_in(parsed_email.subject, parsed_email.text_body, readable_html_text)
      end
    end
  rescue StandardError => error
    Rails.error.report(error, severity: :warning)
    nil
  end

  def deliver_to(recipients, withholding:)
    if withholding
      deliveries.create_for(recipients).each { |delivery| delivery.withhold(withholding) }
    else
      deliveries.create_for(recipients).each(&:deliver_later)
    end
  end

  private
    def tags_within_limit
      errors.add(:tags, "accepts at most #{MAX_TAGS} entries") if tags.size > MAX_TAGS
    end

    # Markup that cannot be read is no markup: the subject and the text are still checked.
    def readable_html_text
      parsed_email.html_text
    rescue StandardError => error
      Rails.error.report(error, severity: :warning)
      nil
    end
end
