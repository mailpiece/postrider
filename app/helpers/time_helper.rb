module TimeHelper
  def local_datetime_tag(datetime, style: :time, **attributes)
    # nbsp holds height until JS fills local time
    tag.time "&nbsp;".html_safe, **attributes, datetime: datetime.to_i, data: { reader_time_target: style, action: "turbo:morph-element->reader-time#refreshTarget" }
  end
end
