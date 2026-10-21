import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { content: String, copied: String }

  async copy(event) {
    event.preventDefault()

    try {
      await navigator.clipboard.writeText(this.contentValue)
      this.#flash(this.copiedValue)
    } catch {}
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
