import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["backdrop"]

  connect() {
    this.escapeHandler = (event) => {
      if (event.key === "Escape" && this.element.open) {
        event.preventDefault()
        event.stopPropagation()
        event.stopImmediatePropagation()
        this.close()
      }
    }
    
    document.addEventListener("keydown", this.escapeHandler, true)
  }

  disconnect() {
    document.removeEventListener("keydown", this.escapeHandler, true)
  }

  close() {
    this.element.close()
  }

  clickOutside(event) {
    if (event.target === this.element || 
        (this.hasBackdropTarget && event.target === this.backdropTarget)) {
      event.preventDefault()
      event.stopPropagation()
      this.close()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      event.stopImmediatePropagation()
      this.close()
    }
  }

  preventClose(event) {
    event.stopPropagation()
  }
}
