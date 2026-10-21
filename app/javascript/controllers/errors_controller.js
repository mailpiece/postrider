import { Controller } from "@hotwired/stimulus"

const FIELD = ".field_with_errors > :is(input, select, textarea):not([type=hidden], :disabled)"

export default class extends Controller {
  connect() {
    if (this.#summaries[0] !== this.element) return

    const fields = this.#fields
    const ids = this.#summaries.map(summary => summary.id)

    fields.forEach(field => {
      field.setAttribute("aria-invalid", "true")
      const described = (field.getAttribute("aria-describedby") || "").split(" ").filter(Boolean)
      field.setAttribute("aria-describedby", [ ...new Set([ ...described, ...ids ]) ].join(" "))
    })

    this.#focus(fields[0] || this.element)
  }

  // Turbo focuses the first [autofocus] element after it renders, which would take focus back from the error.
  #focus(element) {
    this.#scope.querySelectorAll("[autofocus]").forEach(other => other.removeAttribute("autofocus"))
    element.setAttribute("autofocus", "")
    element.focus()
  }

  get #summaries() {
    return Array.from(this.#scope.querySelectorAll("[data-controller~='errors']"))
  }

  get #fields() {
    return Array.from(this.#scope.querySelectorAll(FIELD))
  }

  get #scope() {
    return this.element.closest("form") || this.element.parentElement
  }
}
