module TrailHelper
  def trail_time_tag(at)
    format = at.year == Time.current.year ? "%-d %b, %H:%M" : "%-d %b %Y, %H:%M"
    tag.time l(at, format: format), datetime: at.iso8601, class: "trail__time trail__time--short"
  end
end
