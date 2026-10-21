class Message::Attachment
  ALLOWED_EXTENSIONS = %w[
    jpeg jpg png gif txt pdf docx xlsx pptx csv att ics ical html zip auf xml dwg
  ].freeze

  def self.wrap(raw)
    new(raw) if raw.is_a?(Hash)
  end

  def initialize(raw)
    @attributes = raw.with_indifferent_access
  end

  def name
    @attributes[:name]
  end

  def content_type
    @attributes[:content_type]
  end

  def cid
    @attributes[:cid]
  end

  def decoded
    return @decoded if defined?(@decoded)
    @decoded = decode
  end

  def error
    if name.blank?
      "is missing a name"
    elsif content.blank?
      "#{name} is missing content"
    elsif name.count(".") > 1
      "#{name} must not contain more than one period"
    elsif unsupported_type?
      "#{name} has an unsupported file type"
    elsif decoded.nil? || decoded.bytesize > Relay.max_outbound_message_size
      "are invalid"
    end
  end

  private
    def content
      @attributes[:content]
    end

    def unsupported_type?
      !ALLOWED_EXTENSIONS.include?(File.extname(name).delete_prefix(".").downcase)
    end

    def decode
      Base64.strict_decode64(content.to_s.strip)
    rescue ArgumentError
      nil
    end
end
