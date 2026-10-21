import { Controller } from "@hotwired/stimulus"
import { debounce } from "helpers/timing_helpers"
import { filterMatches, filterMatchRanges } from "helpers/quick_find_helpers"

const UNMARKED = "script, style, template, textarea, svg, mark"

export default class extends Controller {
  static targets = [ "input", "item", "term", "searchLink" ]
  static values = { query: String, limit: Number }

  initialize() {
    this.filter = debounce(this.filter.bind(this), 100)
    this.visitMissingFrame = this.visitMissingFrame.bind(this)
  }

  connect() {
    this.element.addEventListener("turbo:frame-missing", this.visitMissingFrame)
  }

  disconnect() {
    this.element.removeEventListener("turbo:frame-missing", this.visitMissingFrame)
  }

  // A page restored from Turbo's cache, or a box swapped in with a list's frame, keeps the query but not what was typed.
  inputTargetConnected(input) {
    if (!input.value) input.value = this.queryValue
  }

  // Rows that arrive after a query was typed come unfiltered, so each one is filtered as it connects,
  // and whether anything matches is read once per frame, not once per row.
  // A limited list is refiltered as a whole, once per frame, since what it shows depends on the rows before it.
  itemTargetConnected(item) {
    if (this.queryValue.trim()) {
      if (this.limitValue) {
        this.#refilterOnNextFrame()
      } else {
        this.#applyQueryTo(item)
        this.#reflectMatchesOnNextFrame()
      }
    }
  }

  itemTargetDisconnected() {
    if (this.queryValue.trim()) this.#reflectMatchesOnNextFrame()
  }

  // A list rendered without its frame, such as no rows and no filter left, or a 404, shows as a page rather than "Content missing".
  visitMissingFrame(event) {
    event.preventDefault()
    event.detail.visit(event.detail.response)
  }

  filter() {
    this.queryValue = this.inputTarget.value
  }

  clear() {
    if (this.inputTarget.value) {
      this.inputTarget.value = ""
      this.queryValue = ""
      this.inputTarget.focus()
    } else {
      this.inputTarget.blur()
    }
  }

  queryValueChanged() {
    if (this.limitValue) {
      this.#applyLimitedQuery()
    } else {
      this.itemTargets.forEach(item => this.#applyQueryTo(item))
    }

    this.#reflectQuery()
    this.dispatch("changed")
  }

  // Private

  #applyQueryTo(item) {
    this.#show(item, filterMatches(item.textContent, this.queryValue))
  }

  // Shows nothing until something is typed, and then only the first matches.
  #applyLimitedQuery() {
    let shown = 0
    const typed = this.queryValue.trim() !== ""

    this.itemTargets.forEach(item => {
      const visible = typed && shown < this.limitValue && filterMatches(item.textContent, this.queryValue)
      this.#show(item, visible)
      if (visible) shown++
    })
  }

  #show(item, visible) {
    item.toggleAttribute("hidden", !visible)
    this.#unmark(item)
    if (visible && this.queryValue.trim()) this.#mark(item)
  }

  // Only text nodes are wrapped, so row markup, links and their listeners stay as rendered.
  #mark(item) {
    const walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT, {
      acceptNode: node => node.parentElement.closest(UNMARKED) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
    })
    const nodes = []
    while (walker.nextNode()) nodes.push(walker.currentNode)

    nodes.forEach(node => {
      filterMatchRanges(node.data, this.queryValue).reverse().forEach(([ start, end ]) => {
        const match = node.splitText(start)
        match.splitText(end - start)

        const mark = document.createElement("mark")
        mark.className = "filter__match"
        match.replaceWith(mark)
        mark.append(match)
      })
    })
  }

  #unmark(item) {
    item.querySelectorAll("mark.filter__match").forEach(mark => {
      const parent = mark.parentNode
      mark.replaceWith(...mark.childNodes)
      parent.normalize()
    })
  }

  #reflectQuery() {
    const query = this.queryValue.trim()

    this.element.toggleAttribute("data-filtering", query !== "")
    this.#reflectMatches()

    this.termTargets.forEach(term => term.textContent = query)
    this.searchLinkTargets.forEach(link => {
      const url = new URL(link.href)
      url.searchParams.set("q", query)
      link.href = url
    })
  }

  #reflectMatches() {
    this.element.toggleAttribute("data-has-match", this.itemTargets.some(item => !item.hidden))
  }

  #reflectMatchesOnNextFrame() {
    this.reflectingMatches ??= requestAnimationFrame(() => {
      this.reflectingMatches = null
      this.#reflectMatches()
    })
  }

  #refilterOnNextFrame() {
    this.refiltering ??= requestAnimationFrame(() => {
      this.refiltering = null
      this.queryValueChanged()
    })
  }
}
