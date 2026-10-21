class SmtpSubmission
  DIRECTIVE_HEADERS = /\A(x-postrider-tags|x-list-unsubscribe)[ \t]*:/i

  RECEIVER_HEADERS =
    /\A(authentication-results|received-spf|received|arc-seal|arc-message-signature|arc-authentication-results)[ \t]*:/i

  MESSAGE_ID_HEADER = /\Amessage-id[ \t]*:/i

  DATE_HEADER = /\Adate[ \t]*:/i

  LIST_UNSUBSCRIBE_HEADER = /\A(list-unsubscribe|list-unsubscribe-post)[ \t]*:/i

  IDENTITY_HEADERS = %w[ from sender ]

  def initialize(raw)
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
      header_records.reject do |record|
        record.match?(DIRECTIVE_HEADERS) || record.match?(RECEIVER_HEADERS) ||
          replaced_message_id?(record) || replaced_list_unsubscribe?(record)
      end
    end

    def replaced_message_id?(record)
      replacing_message_id? && record.match?(MESSAGE_ID_HEADER)
    end

    def message_id_records
      replacing_message_id? ? [ generated_message_id_record ] : []
    end

    # Multiple or foreign Message-IDs are untrusted — replace all of them.
    def replacing_message_id?
      from_domain.present? && (records_for("message-id").size != 1 || message_id_host != from_domain)
    end

    def generated_message_id_record
      @generated_message_id_record ||= "Message-ID: <#{SecureRandom.uuid}@#{from_domain}>"
    end

    def message_id_host
      header_value("message-id")&.downcase&.slice(/@([^@>]+)>?\z/, 1)
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
      @from_domain ||= EmailAddress.extract(header_value("from"))&.split("@")&.last&.downcase
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
      header_records.select { |record| record.match?(/\A#{Regexp.escape(name)}[ \t]*:/i) }
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
