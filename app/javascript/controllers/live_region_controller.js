import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "region", "announcement" ]

  announcementTargetConnected(element) {
    if (document.documentElement.hasAttribute("data-turbo-preview") || element.hasAttribute("data-announced")) return

    element.setAttribute("data-announced", "")
    this.#announce(element.textContent.trim())
  }

  #announce(text) {
    if (this.hasRegionTarget) this.regionTarget.textContent = ""

    // A region whose text changes in the same frame it was cleared or inserted is not read out.
    setTimeout(() => {
      if (this.hasRegionTarget) this.regionTarget.textContent = text
    }, 100)
  }
}
