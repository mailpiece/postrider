class SmtpSubmission
  # A name may be folded before its colon, so each pattern allows any whitespace there.
  DIRECTIVE_HEADERS = /\A(x-postrider-tags|x-list-unsubscribe)\s*:/i

  RECEIVER_HEADERS =
    /\A(authentication-results|received-spf|received|arc-seal|arc-message-signature|arc-authentication-results)\s*:/i

  MESSAGE_ID_HEADER = /\Amessage-id\s*:/i

  REFERENCE_HEADERS = /\A(in-reply-to|references)\s*:/i

  REFERENCE = /<[^<>]*>/

  DATE_HEADER = /\Adate\s*:/i

  LIST_UNSUBSCRIBE_HEADER = /\A(list-unsubscribe|list-unsubscribe-post)\s*:/i

  IDENTITY_HEADERS = %w[ from sender ]

  # The sending domain decides which references name mail it sent, and so may be mapped to their stand-ins.
  def initialize(raw, domain:)
    @domain = domain
    @raw_headers, @raw_body = raw.gsub(/\r?\n/, "\r\n").gsub(/\r(?!\n)/, "").split("\r\n\r\n", 2)
    @raw_headers ||= ""
    @raw_body ||= ""
  end

  def valid?
    header?("from") && IDENTITY_HEADERS.all? { |name| asserted_once?(name) } && header?("to")
  end

  def identities
    IDENTITY_HEADERS.filter_map { |name| EmailAddress.extract(header_value(name)) }
  end

  def tags
    header_value("x-postrider-tags").to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def raw
    (kept_header_records + list_unsubscribe_records + message_id_records + date_records).join("\r\n") +
      "\r\n\r\n" + @raw_body
  end

  private
    def asserted_once?(name)
      if header?(name)
        records_for(name).one? && EmailAddress.extract_list(header_value(name)).one?
      else
        true
      end
    end

    def header_records
      @header_records ||= @raw_headers.split(/\r\n(?![ \t])/)
    end

    def kept_header_records
      header_records.reject { |record| dropped?(record) }.map { |record| rewritten(record) }
    end

    def dropped?(record)
      record.match?(DIRECTIVE_HEADERS) || record.match?(RECEIVER_HEADERS) ||
        replaced_message_id?(record) || replaced_list_unsubscribe?(record)
    end

    def replaced_message_id?(record)
      replacing_message_id? && record.match?(MESSAGE_ID_HEADER)
    end

    # Nothing can thread on a missing, repeated or malformed Message-ID, so stamp our own.
    def replacing_message_id?
      from_domain.present? && !(records_for("message-id").one? && MessageId.well_formed?(header_value("message-id")))
    end

    def rewritten(record)
      if from_domain.blank?
        record
      elsif record.match?(MESSAGE_ID_HEADER)
        "Message-ID: #{MessageId.parse(header_value("message-id")).at(from_domain)}"
      elsif record.match?(REFERENCE_HEADERS)
        with_sent_references_mapped(record)
      else
        record
      end
    end

    # One ID per line, so stand-ins longer than the IDs they replace never push a line past 998.
    def with_sent_references_mapped(record)
      if references[record].any? { |reference| sent?(reference) }
        "#{record.split(":", 2).first.strip}: " +
          references[record].map { |reference| sent?(reference) ? stand_in_for(reference) : reference }.join("\r\n ")
      else
        record
      end
    end

    def references
      @references ||= header_records.grep(REFERENCE_HEADERS).index_with { |record| record.scan(REFERENCE) }
    end

    # Only a reference to our own rewritten mail is mapped: someone else's machine-name ID
    # is what their side threads on, and mapping it would hide nothing.
    def sent?(reference)
      sent_stand_ins.include?(stand_in_for(reference))
    end

    def stand_in_for(reference)
      if (id = MessageId.parse(reference))&.machine_host?
        id.stand_in_at(from_domain)
      end
    end

    # A stand-in carries the From domain, and a token sends only for its own domain,
    # so only mail this domain sent can match.
    def sent_stand_ins
      @sent_stand_ins ||= if reference_stand_ins.any?
        @domain.messages.where(mail_message_id: reference_stand_ins).pluck(:mail_message_id).to_set
      else
        Set.new
      end
    end

    def reference_stand_ins
      references.values.flatten.filter_map { |reference| stand_in_for(reference) }
    end

    def message_id_records
      replacing_message_id? ? [ generated_message_id_record ] : []
    end

    def generated_message_id_record
      @generated_message_id_record ||= "Message-ID: <#{SecureRandom.uuid}@#{from_domain}>"
    end

    def date_records
      date_present? ? [] : [ generated_date_record ]
    end

    def date_present?
      header_records.any? { |record| record.match?(DATE_HEADER) }
    end

    def generated_date_record
      @generated_date_record ||= "Date: #{Time.current.rfc2822}"
    end

    def from_domain
      @from_domain ||= Domain.name_for(header_value("from"))
    end

    def replaced_list_unsubscribe?(record)
      replacing_list_unsubscribe? && record.match?(LIST_UNSUBSCRIBE_HEADER)
    end

    def list_unsubscribe_records
      if (unsubscribe = ListUnsubscribe.new(list_unsubscribe_directive)).present?
        if unsubscribe.one_click?
          [ "List-Unsubscribe: #{unsubscribe}", "List-Unsubscribe-Post: #{ListUnsubscribe::ONE_CLICK_POST}" ]
        else
          [ "List-Unsubscribe: #{unsubscribe}" ]
        end
      else
        []
      end
    end

    def replacing_list_unsubscribe?
      list_unsubscribe_directive.present?
    end

    def list_unsubscribe_directive
      header_value("x-list-unsubscribe").presence
    end

    def records_for(name)
      header_records.select { |record| record.match?(/\A#{Regexp.escape(name)}\s*:/i) }
    end

    def header?(name)
      records_for(name).any?
    end

    def header_value(name)
      if record = records_for(name).first
        record.split(":", 2).last.gsub(/\r\n[ \t]+/, " ").strip
      end
    end
end
