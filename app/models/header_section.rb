# The fields above a message's first empty line.
module HeaderSection
  def self.of(raw)
    raw.byteslice(0, raw.b.index(/\r?\n\r?\n/) || raw.bytesize)
  end
end
