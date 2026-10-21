# Independent of the signing path so signatures are checked against RFC 6376, not our own canon.
module DkimTestHelper
  def verify_dkim(signed_message, public_key)
    raw_headers, = signed_message.split("\r\n\r\n", 2)
    lines = raw_headers.gsub(/\r\n(?=[ \t])/, "").split("\r\n")
    dkim_line = lines.find { |line| line.match?(/\Adkim-signature:/i) }
    tags = parse_dkim_tags(dkim_line)

    signature = Base64.decode64(tags["b"].gsub(/\s+/, ""))
    signed = signed_headers(lines, tags["h"].split(":"))
    signed << relaxed_header(dkim_line.sub(/b=[^;]*\z/, "b="))

    public_key.verify(OpenSSL::Digest.new("SHA256"), signature, signed.join("\r\n"))
  end

  def parse_dkim_tags(dkim_line)
    dkim_line.split(":", 2).last.split(";").each_with_object({}) do |pair, tags|
      key, value = pair.split("=", 2)
      tags[key.strip] = value.to_s.strip if key
    end
  end

  private
    # RFC 6376 §5.4.2: each h= name takes the next instance bottom-up; surplus names contribute nothing.
    def signed_headers(lines, names)
      instances = Hash.new { |hash, name| hash[name] = lines.select { |line| line.split(":", 2).first.strip.casecmp?(name) } }

      names.filter_map do |name|
        if line = instances[name.downcase].pop
          relaxed_header(line)
        end
      end
    end

    # RFC 6376 §3.4.2 relaxed header canonicalization.
    def relaxed_header(line)
      name, value = line.split(":", 2)
      "#{name.strip.downcase}:#{value.gsub(/[ \t]+/, ' ').strip}"
    end
end
