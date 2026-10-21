module ToolsHelper
  def project_meta_tag(*facts)
    if (facts = facts.compact_blank).any?
      tag.p safe_join(facts, " · "), class: "project__meta"
    end
  end

  def project_fact(label, value)
    "#{label}: #{value}"
  end

  def few_to_sentence(items)
    if items.size > 4
      to_sentence [ *items.first(3), "#{items.size - 3} more" ]
    else
      to_sentence items
    end
  end

  def tool_tag(title, path, &block)
    link_to(path, class: "tool") { tool_contents(title, &block) }
  end

  def tool_row_tag(title, meta: nil, inactive: false)
    tag.li class: class_names("row", "row--inactive": inactive) do
      tool_row_body(title, meta)
    end
  end

  def tool_more_tag(rows, shown)
    remaining = rows.size - shown.size
    tag.p "and #{remaining} more", class: "tool__more" if remaining.positive?
  end

  private
    def tool_contents(title, &)
      safe_join [ tag.h2(title, class: "tool__title"), tag.div(class: "tool__panel", &) ]
    end

    def tool_row_body(title, meta)
      contents = safe_join [ tag.strong(title, class: "row__title"), (tag.span(meta, class: "row__meta") if meta.present?) ]

      tag.span contents, class: "row__body"
    end
end
