import { Controller } from "@hotwired/stimulus"

// The page's own crumb is markup in every view, so it is found here rather than marked as a target.
export default class extends Controller {
  static classes = [ "expanded" ]

  connect() {
    this.refresh()
    document.fonts.ready.then(() => this.refresh())
  }

  refresh() {
    const name = this.#name
    if (!name) return

    const expanded = this.#crumbs.classList.contains(this.expandedClass)
    const interactive = expanded || name.scrollWidth > name.clientWidth

    if (interactive) {
      name.setAttribute("tabindex", "0")
      name.setAttribute("role", "button")
      name.setAttribute("aria-expanded", expanded)
    } else {
      name.removeAttribute("tabindex")
      name.removeAttribute("role")
      name.removeAttribute("aria-expanded")
    }
  }

  toggle(event) {
    const name = this.#name
    if (!name?.hasAttribute("tabindex") || !name.contains(event.target)) return

    event.preventDefault()
    this.#crumbs.classList.toggle(this.expandedClass)
    this.refresh()
  }

  get #crumbs() {
    return this.element.querySelector(".breadcrumbs")
  }

  get #name() {
    return this.#crumbs?.querySelector(":scope > strong")
  }
}
