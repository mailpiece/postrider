class InboundAuthentication
  def self.strip(data)
    new(data).stripped
  end

  def self.verdicts(data, ip:, helo:, mail_from:)
    new(data, ip:, helo:, mail_from:).verdicts
  end

  def initialize(data, ip: nil, helo: nil, mail_from: nil)
    @data = data.gsub(/\r?\n/, "\r\n")
    @ip = ip
    @helo = helo
    @mail_from = mail_from
  end

  def stripped
    data_without_authentication_results
  end

  def verdicts
    MailAuth.new(@data, ip: @ip, helo: @helo, mail_from: @mail_from).verdicts
  end

  private
    def data_without_authentication_results
      headers, separator, body = @data.partition("\r\n\r\n")

      if separator.empty?
        genuine_fields(headers)
      else
        genuine_fields(headers + "\r\n") + "\r\n" + body
      end
    end

    def genuine_fields(headers)
      fields_in(headers).reject { |field| authentication_results?(field) }.join
    end

    def fields_in(headers)
      headers.lines.each_with_object([]) do |line, fields|
        if fields.any? && line.start_with?(" ", "\t")
          fields.last << line
        else
          fields << line
        end
      end
    end

    def authentication_results?(field)
      field.match?(/\AAuthentication-Results[ \t]*:/i)
    end
end
