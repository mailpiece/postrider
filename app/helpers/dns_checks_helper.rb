module DnsChecksHelper
  STATUS_LABELS = { "ok" => "OK", "missing" => "Missing", "invalid" => "Invalid" }.freeze
  STATUS_SEMANTICS = { "ok" => "success", "missing" => "warning", "invalid" => "error" }.freeze

  def dns_status_label(status)
    if status
      STATUS_LABELS.fetch(status, status.humanize)
    else
      "Not checked"
    end
  end

  def dns_status_tag(status)
    tag.span dns_status_label(status), class: "status status--#{dns_status_semantic(status)}"
  end

  private
    def dns_status_semantic(status)
      STATUS_SEMANTICS.fetch(status, "neutral")
    end
end
