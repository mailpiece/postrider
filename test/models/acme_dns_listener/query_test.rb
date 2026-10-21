require "test_helper"

class AcmeDnsListener::QueryTest < ActiveSupport::TestCase
  test "parses the header and the first question" do
    query = AcmeDnsListener::Query.parse(packet(labels("_ACME-Challenge", "Example", "com"), id: 0x1234, flags: 0x0100))

    assert_equal 0x1234, query.id
    assert query.rd
    assert_equal "_acme-challenge.example.com", query.name
    assert_equal 16, query.type
    assert_equal 1, query.klass
    assert_equal labels("_ACME-Challenge", "Example", "com") + [ 16, 1 ].pack("nn"), query.question
  end

  test "parses without recursion desired" do
    assert_not AcmeDnsListener::Query.parse(packet(labels("example", "com"), flags: 0)).rd
  end

  test "is nil for a short packet" do
    assert_nil AcmeDnsListener::Query.parse("")
    assert_nil AcmeDnsListener::Query.parse("garbage")
  end

  test "is nil for a response" do
    assert_nil AcmeDnsListener::Query.parse(packet(labels("example", "com"), flags: 0x8100))
  end

  test "is nil for an opcode other than query" do
    assert_nil AcmeDnsListener::Query.parse(packet(labels("example", "com"), flags: 0x0900))
  end

  test "is nil without a question" do
    assert_nil AcmeDnsListener::Query.parse(packet(labels("example", "com"), qdcount: 0))
  end

  test "is nil for a compression pointer in the name" do
    assert_nil AcmeDnsListener::Query.parse(packet("\x07example\xC0\x0C".b))
    assert_nil AcmeDnsListener::Query.parse(packet("\xC0\x0C".b))
  end

  test "is nil for a label over 63 bytes" do
    assert_nil AcmeDnsListener::Query.parse(packet(labels("a" * 64, "com")))
    assert_not_nil AcmeDnsListener::Query.parse(packet(labels("a" * 63, "com")))
  end

  test "is nil for a name over 255 bytes" do
    assert_nil AcmeDnsListener::Query.parse(packet(labels(*[ "a" * 63 ] * 4)))
    assert_not_nil AcmeDnsListener::Query.parse(packet(labels(*[ "a" * 63 ] * 3, "a" * 61)))
  end

  test "is nil for a label running past the end of the packet" do
    assert_nil AcmeDnsListener::Query.parse(header + "\x07exam".b)
    assert_nil AcmeDnsListener::Query.parse(header + "\x07example".b)
  end

  test "is nil without a type and class" do
    assert_nil AcmeDnsListener::Query.parse(header + labels("example", "com"))
    assert_nil AcmeDnsListener::Query.parse(header + labels("example", "com") + "\x00\x10\x00".b)
  end

  private
    def header(id: 1, flags: 0x0100, qdcount: 1)
      [ id, flags, qdcount, 0, 0, 0 ].pack("n6")
    end

    def packet(name, type: 16, klass: 1, **header_fields)
      header(**header_fields) + name + [ type, klass ].pack("nn")
    end

    def labels(*names)
      names.map { |label| [ label.bytesize ].pack("C") + label.b }.join + "\x00".b
    end
end
