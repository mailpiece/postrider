import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { confirmation: String }

  submit({ target }) {
    if (target.checked && this.confirmationValue && !confirm(this.confirmationValue)) {
      target.checked = false
    } else {
      this.element.requestSubmit()
    }
  }
}
