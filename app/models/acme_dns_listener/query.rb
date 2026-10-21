# The header and first question of a DNS query, read by hand so an unsolicited
# packet meets nothing but bounds checks.
class AcmeDnsListener::Query
  HEADER_LENGTH = 12
  MAX_LABEL_LENGTH = 63
  MAX_NAME_LENGTH = 255

  attr_reader :id, :rd, :name, :type, :klass, :question

  class << self
    def parse(packet)
      if packet.bytesize >= HEADER_LENGTH
        id, flags, qdcount = packet.unpack("nnn")

        if flags.nobits?(0xF800) && qdcount > 0 && (labels, type, klass, length = read_question(packet))
          new(id:, rd: flags.anybits?(0x0100), labels:, type:, klass:, question: packet.byteslice(HEADER_LENGTH, length))
        end
      end
    end

    private
      def read_question(packet)
        if (labels, name_length = read_name(packet)) && (fields = packet.byteslice(HEADER_LENGTH + name_length, 4)) && fields.bytesize == 4
          [ labels, *fields.unpack("nn"), name_length + 4 ]
        end
      end

      # Labels only: a compression pointer or any other label type fails the length check.
      def read_name(packet)
        labels = []
        offset = HEADER_LENGTH

        while (length = packet.getbyte(offset))
          offset += 1
          break if length.zero?

          return nil if length > MAX_LABEL_LENGTH || offset + length + 1 - HEADER_LENGTH > MAX_NAME_LENGTH
          return nil unless (label = packet.byteslice(offset, length)) && label.bytesize == length

          labels << label
          offset += length
        end

        [ labels, offset - HEADER_LENGTH ] if length
      end
  end

  def initialize(id:, rd:, labels:, type:, klass:, question:)
    @id = id
    @rd = rd
    @name = labels.join(".").downcase
    @type = type
    @klass = klass
    @question = question
  end
end
