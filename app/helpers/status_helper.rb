module StatusHelper
  STATUS_SEMANTICS = {
    "delivered" => "success",
    "forwarded" => "success",
    "accepted" => "success",
    "completed" => "success",
    "processing" => "progress",
    "in_progress" => "progress",
    "deferred" => "progress",
    "failed" => "error",
    "bounced" => "error",
    "exhausted" => "error",
    "errored" => "error",
    "suppressed" => "muted",
    "withheld" => "muted",
    "discarded" => "muted",
    "pending" => "waiting",
    "queued" => "waiting"
  }.freeze

  WRONG_SEMANTICS = %w[ error warning ].freeze

  STATUS_FORMS = {
    word: nil,
    badge: "status--badge"
  }.freeze

  def status_tag(status, form: :word, **options)
    tag.span status.humanize,
      class: class_names("status", "status--#{status_semantic(status)}", STATUS_FORMS.fetch(form), options.delete(:class)), **options
  end

  # What a row says of its state in its meta line: coloured only when something is wrong.
  def row_status(status, detail = nil)
    words = [ status.humanize, detail ].compact.join(" ")

    if WRONG_SEMANTICS.include?(status_semantic(status))
      tag.span words, class: "status status--#{status_semantic(status)}"
    else
      words
    end
  end

  private
    def status_semantic(status)
      STATUS_SEMANTICS.fetch(status.to_s, "neutral")
    end
end
