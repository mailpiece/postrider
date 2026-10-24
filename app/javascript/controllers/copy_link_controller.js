import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "icon" ]
  static values = { content: String, copied: String }

  async copy(event) {
    event.preventDefault()

    try {
      await navigator.clipboard.writeText(this.contentValue)
      this.#flash(this.copiedValue)
      this.#confirm()
    } catch {}
  }

  select(event) {
    event.target.select()
  }

  #confirm() {
    if (!this.hasIconTarget) return

    clearTimeout(this.confirmTimeout)
    this.iconTarget.classList.replace("icon--copy-paste", "icon--check")
    this.confirmTimeout = setTimeout(() => this.iconTarget.classList.replace("icon--check", "icon--copy-paste"), 1000)
  }

  #flash(message) {
    const frame = document.getElementById("flash")
    const template = frame?.querySelector("[data-flash-template]")
    if (!template) return

    const flash = template.content.cloneNode(true)
    flash.querySelector(".flash__inner").textContent = message

    frame.appendChild(flash)
  }
}
