import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["message"]

  connect() {
    // Auto-hide after 5 seconds
    setTimeout(() => {
      this.hide()
    }, 5000)
  }

  hide() {
    this.messageTargets.forEach(message => {
      message.style.transition = "opacity 0.3s ease-out, transform 0.3s ease-out"
      message.style.opacity = "0"
      message.style.transform = "translateX(100%)"
      
      // Remove from DOM after animation
      setTimeout(() => {
        if (message.parentNode) {
          message.parentNode.removeChild(message)
        }
      }, 300)
    })
  }

  // Allow manual dismissal by clicking
  dismiss(event) {
    const message = event.currentTarget.closest('[data-flash-target="message"]')
    if (message) {
      message.style.transition = "opacity 0.3s ease-out, transform 0.3s ease-out"
      message.style.opacity = "0"
      message.style.transform = "translateX(100%)"
      
      setTimeout(() => {
        if (message.parentNode) {
          message.parentNode.removeChild(message)
        }
      }, 300)
    }
  }
}
