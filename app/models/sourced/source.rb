class Sourced::Source
  PARSE_BYTES = 256.kilobytes

  attr_reader :raw, :subject, :message_id

  # A source built again for each recipient of one message passes the same +key+, so its copy is stored once.
  def initialize(raw, key: nil)
    @raw = raw
    @key = key

    parsed = ParsedEmail.new(raw.to_s.byteslice(0, PARSE_BYTES))
    @subject = parsed.subject.to_s.truncate(255)
    @message_id = parsed.message_id&.truncate(255)
  end

  def blob
    @blob ||= stored_blob ||
      ActiveStorage::Blob.create_and_upload!(key: @key, io: StringIO.new(raw), filename: "raw.eml", content_type: "message/rfc822")
  end

  private
    def stored_blob
      ActiveStorage::Blob.find_by(key: @key) if @key
    end
end
