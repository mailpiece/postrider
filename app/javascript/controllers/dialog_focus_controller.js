import { Controller } from "@hotwired/stimulus"

const TABBABLE = "a[href], button:not([disabled]), input:not([disabled]):not([type=hidden]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
const FIELD = "input, select, textarea"
const TYPING = "input, textarea, select, [contenteditable], lexxy-editor"

export default class extends Controller {
  static targets = [ "trigger" ]

  #focusInside = false
  #placed = null

  connect() {
    this.element.addEventListener("dialog:show", this.#opened)
    this.element.addEventListener("dialog:close", this.#closed)
    this.element.addEventListener("keydown", this.#trap)
    this.element.addEventListener("turbo:frame-load", this.#loaded)
    document.addEventListener("focusin", this.#trackFocus)
    document.addEventListener("pointerdown", this.#trackPointer, true)
  }

  disconnect() {
    this.element.removeEventListener("dialog:show", this.#opened)
    this.element.removeEventListener("dialog:close", this.#closed)
    this.element.removeEventListener("keydown", this.#trap)
    this.element.removeEventListener("turbo:frame-load", this.#loaded)
    document.removeEventListener("focusin", this.#trackFocus)
    document.removeEventListener("pointerdown", this.#trackPointer, true)
  }

  // Bound at the document, for a dialog that stays open with focus outside it. The up crumb reads the prevented default as the key being taken.
  closeFromOutside(event) {
    if (this.#open && !event.defaultPrevented && !event.target.closest(TYPING)) {
      event.preventDefault()
      this.#dialogController.close()
    }
  }

  #opened = (event) => {
    if (event.target === this.element) {
      this.#reflectExpanded(true)
      this.#placed = this.#focusFirst()
    }
  }

  #closed = (event) => {
    if (event.target === this.element) {
      this.#reflectExpanded(false)

      if (this.#focusInside) this.#opener?.focus()
      this.#focusInside = false
    }
  }

  #loaded = ({ target }) => {
    if (this.#open && this.#dialog.contains(target) && document.activeElement === this.#placed) {
      this.#placed = this.#focusFirst()
    }
  }

  #trap = (event) => {
    if (event.key !== "Tab" || !this.#open || !this.#dialog.contains(event.target)) return

    const tabbables = this.#tabbables
    const index = tabbables.indexOf(event.target)
    const leaving = event.shiftKey ? index <= 0 : index === -1 || index === tabbables.length - 1

    if (leaving) {
      event.preventDefault()
      const edge = event.shiftKey ? tabbables.at(-1) : tabbables.at(0)
      edge?.focus()
    }
  }

  // Closing a dialog hands focus back natively before dialog:close fires, so only focus moving while open counts.
  #trackFocus = ({ target }) => {
    if (this.#open) this.#focusInside = this.#dialog.contains(target)
  }

  #trackPointer = ({ target }) => {
    if (!this.#dialog?.contains(target)) this.#focusInside = false
  }

  #focusFirst() {
    const tabbables = this.#tabbables
    const first = tabbables.find(element => element.autofocus) || tabbables.find(element => element.matches(FIELD)) || tabbables[0]

    first?.focus()
    return document.activeElement
  }

  #reflectExpanded(expanded) {
    this.triggerTargets.forEach(trigger => trigger.setAttribute("aria-expanded", expanded))
  }

  // Safari never focuses a clicked button and a hotkey clicks without focusing, so the opener is read from the markup.
  get #opener() {
    return this.triggerTargets[0] || Array.from(this.element.querySelectorAll("button, a[href]")).find(control => !this.#dialog.contains(control))
  }

  get #tabbables() {
    return Array.from(this.#dialog.querySelectorAll(TABBABLE)).filter(element => element.checkVisibility())
  }

  get #open() {
    return this.#dialog?.open
  }

  get #dialog() {
    return this.#dialogController?.dialogTarget
  }

  get #dialogController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "dialog")
  }
}
