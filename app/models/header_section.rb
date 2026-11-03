# The fields above a message's first empty line. Real mail keeps them to a few
# kilobytes, so past MAX_BYTES a message is refused rather than read field by field.
module HeaderSection
  MAX_BYTES = 1.megabyte

  def self.oversized?(raw)
    raw.bytesize > MAX_BYTES && !raw.byteslice(0, MAX_BYTES + 4).b.match?(/\r?\n\r?\n/)
  end
end
