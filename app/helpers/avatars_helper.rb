require "zlib"

module AvatarsHelper
  AVATAR_COLORS = %w[
    #AF2E1B #CC6324 #3B4B59 #BFA07A #ED8008 #ED3F1C #BF1B1B #736B1E #D07B53
    #736356 #AD1D1D #BF7C2A #C09C6F #698F9C #7C956B #5D618F #3B3633 #67695E
  ].freeze

  def avatar_tag(name, email, **options)
    initials = avatar_initials(name, email)
    squeezed = initials.size >= 3

    tag.span squeezed ? tag.span(initials, class: "avatar__letters") : initials,
      class: class_names("avatar avatar--initials", options.delete(:class), "avatar--squeezed": squeezed),
      style: "background-color: #{avatar_background_color(email)};",
      aria: { hidden: true }, **options
  end

  private
    def avatar_background_color(seed)
      AVATAR_COLORS[Zlib.crc32(seed.to_s) % AVATAR_COLORS.size]
    end

    def avatar_initials(name, email)
      source = name.presence || email.to_s.split("@").first.to_s
      initials = source.scan(/\b\p{L}/)
      initials = source.scan(/\p{L}/).first(2) if initials.size < 2
      initials.first(3).join.upcase
    end
end
