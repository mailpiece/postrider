import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static classes = [ "shown" ]

  connect() {
    this.toggle()
  }

  toggle() {
    this.element.classList.toggle(this.shownClass, window.scrollY > window.innerHeight)
  }

  scroll() {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    window.scrollTo({ top: 0, behavior: reduced ? "instant" : "smooth" })
  }
}
