import { Controller } from "@hotwired/stimulus"

const ROWS = ".rows > li[id], .trail > [id], .message[id]"
const CHANGES = [ "replace", "update" ]

export default class extends Controller {
  #known = null

  markStream(event) {
    const { newStream, render } = event.detail

    event.detail.render = async (streamElement) => {
      const known = this.#rowIds
      await render(streamElement)
      this.#markArrivals(known)
      if (CHANGES.includes(newStream.action)) this.#markChanged(newStream)
    }
  }

  rememberRows(event) {
    if (event.detail.renderMethod === "morph") this.#known = this.#rowIds
  }

  markMorphed() {
    if (this.#known) this.#markArrivals(this.#known)
    this.#known = null
  }

  clear({ target, animationName }) {
    if (animationName === "tint-fade") target.classList.remove("tint-fade")
  }

  #markArrivals(known) {
    document.querySelectorAll(ROWS).forEach(row => {
      if (!known.has(row.id)) this.#mark(row)
    })
  }

  #markChanged(stream) {
    stream.targetElements.filter(target => target.matches(ROWS)).forEach(row => this.#mark(row))
  }

  #mark(row) {
    row.classList.add("tint-fade")
  }

  get #rowIds() {
    return new Set(Array.from(document.querySelectorAll(ROWS), row => row.id))
  }
}
