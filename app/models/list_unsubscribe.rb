class ListUnsubscribe
  ONE_CLICK_POST = "List-Unsubscribe=One-Click"

  BARE_URI = /\A[^<>,\s]+\z/

  def initialize(value)
    @value = value.to_s.strip
  end

  def present?
    @value.present?
  end

  # RFC 2369 needs angle brackets; only reframe a lone bare URI — don't rewrite structured values.
  def to_s
    if @value.include?("<") || !@value.match?(BARE_URI)
      @value
    else
      "<#{@value}>"
    end
  end

  # One-Click is only honest when an https URI is present (not a mailto query that mentions one).
  def one_click?
    uris.any? { |uri| uri.match?(%r{\Ahttps://}i) }
  end

  private
    def uris
      to_s.scan(/<([^>]*)>/).flatten.map(&:strip)
    end
end
