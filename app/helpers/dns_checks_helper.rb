module DnsChecksHelper
  STATUS_LABELS = { "ok" => "OK", "missing" => "Missing", "invalid" => "Invalid" }.freeze
  STATUS_SEMANTICS = { "ok" => "success", "missing" => "warning", "invalid" => "error" }.freeze

  DnsRecordItem = Data.define(:record, :title, :status, :error, :found, :checked)

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

  # Problems first. A record no check looks at is listed without a status, after them.
  def relay_dns_records(dns_check)
    items = dns_check.dns_records.map do |record|
      if check = record.check
        dns_record_item(record, record.purpose, dns_check.public_send("#{check}_status"), dns_check.public_send("#{check}_error"))
      else
        dns_record_item(record, record.purpose, nil, nil, checked: false)
      end
    end

    items.partition { it.checked && !it.found }.flatten
  end

  private
    def dns_record_item(record, title, status, error, checked: true)
      DnsRecordItem.new(record:, title:, status:, error:, found: status == "ok" && error.blank?, checked:)
    end

    def dns_status_semantic(status)
      STATUS_SEMANTICS.fetch(status, "neutral")
    end
end
