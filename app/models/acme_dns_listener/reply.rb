# A reply to one query, built by hand: the header, the question as asked, and
# records owned by that question through the one compression pointer DNS allows.
class AcmeDnsListener::Reply
  IN = 1
  NS = 2
  SOA = 6
  TXT = 16

  NOERROR = 0
  REFUSED = 5
  TTL = 0
  QUESTION_POINTER = "\xC0\x0C".b

  def initialize(query, aa: false, rcode: NOERROR)
    @query = query
    @aa = aa
    @rcode = rcode
    @answers = []
    @authorities = []
  end

  def txt(content)
    @answers << record(TXT, [ content.bytesize ].pack("C") + content.b)
  end

  def ns(hostname)
    @answers << record(NS, encode_name(hostname))
  end

  def soa(hostname)
    @answers << soa_record(hostname)
  end

  def nodata(hostname)
    @authorities << soa_record(hostname)
  end

  def encode
    header + @query.question + @answers.join + @authorities.join
  end

  private
    def header
      flags = 0x8000 | (@aa ? 0x0400 : 0) | (@query.rd ? 0x0100 : 0) | @rcode
      [ @query.id, flags, 1, @answers.size, @authorities.size, 0 ].pack("n6")
    end

    def soa_record(hostname)
      record(SOA, encode_name(hostname) + encode_name("hostmaster.#{hostname}") + [ Time.now.to_i, 3600, 600, 86400, 0 ].pack("N5"))
    end

    def record(type, rdata)
      QUESTION_POINTER + [ type, IN, TTL, rdata.bytesize ].pack("nnNn") + rdata
    end

    def encode_name(hostname)
      hostname.chomp(".").split(".").map { |label| [ label.bytesize ].pack("C") + label.b }.join + "\x00".b
    end
end
