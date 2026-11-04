module StatusHelper
  STATUS_SEMANTICS = {
    "delivered" => "success",
    "forwarded" => "success",
    "accepted" => "neutral",
    "completed" => "success",
    "processing" => "progress",
    "in_progress" => "progress",
    "deferred" => "progress",
    "held" => "warning",
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

  STATUS_FORMS = {
    word: nil,
    badge: "status--badge"
  }.freeze

  def status_tag(status, form: :word, **options)
    tag.span status.humanize,
      class: class_names("status", "status--#{status_semantic(status)}", STATUS_FORMS.fetch(form), options.delete(:class)), **options
  end

  # The colour a status lends to whatever else carries it.
  def status_class(status)
    "status--#{status_semantic(status)}"
  end

  private
    def status_semantic(status)
      STATUS_SEMANTICS.fetch(status.to_s, "neutral")
    end
end
