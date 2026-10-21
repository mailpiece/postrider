class EmailAddress
  class << self
    def format(value, name: nil)
      email, embedded_name = parse(value)
      if email.present?
        display_name = name.presence || embedded_name
        if display_name.present?
          Mail::Address.new.tap do |address|
            address.address = email
            address.display_name = display_name
          end.format
        else
          email
        end
      end
    end

    def format_list(values)
      list(values).filter_map { |value| format(value) }
    end

    def extract_list(values)
      list(values).filter_map { |value| extract(value) }
    end

    def extract(value)
      if value.present?
        parse(value).first
      end
    end

    private
      def list(values)
        Array(values).flat_map { |value| value.is_a?(String) ? split(value) : value }
      end

      def split(string)
        addresses = Mail::AddressList.new(string).addresses
        addresses.any? ? addresses.map(&:format) : [ string ]
      rescue StandardError
        [ string ]
      end

      def parse(value)
        if value.blank?
          [ nil, nil ]
        elsif value.is_a?(String)
          if parsed = parse_rfc822(value)
            [ parsed.address, parsed.display_name.presence ]
          else
            [ value.strip.presence, nil ]
          end
        else
          [ nil, nil ]
        end
      end

      def parse_rfc822(value)
        Mail::Address.new(value.to_s.strip)
      rescue Mail::Field::ParseError
        nil
      end
  end
end
