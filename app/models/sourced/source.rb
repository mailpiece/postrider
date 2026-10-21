class Sourced::Source
  PARSE_BYTES = 256.kilobytes

  attr_reader :raw, :subject, :message_id

  def initialize(raw)
    @raw = raw

    parsed = ParsedEmail.new(raw.to_s.byteslice(0, PARSE_BYTES))
    @subject = parsed.subject.to_s.truncate(255)
    @message_id = parsed.message_id&.truncate(255)
  end

  def blob
    @blob ||= ActiveStorage::Blob.create_and_upload!(io: StringIO.new(raw), filename: "raw.eml", content_type: "message/rfc822")
  end
end
