import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { 
    programSlug: String,
    originalParams: String 
  }
  static targets = ["historyButton"]

  connect() {
    // Show history buttons only if there's history to go back to
    this.checkHistoryAvailability()
  }

  checkHistoryAvailability() {
    if (window.history.length > 1) {
      this.historyButtonTargets.forEach(button => {
        button.classList.remove('hidden')
      })
    }
  }

  goBack(event) {
    event.preventDefault()
    window.history.back()
  }

  verify(event) {
    event.preventDefault()
    
    const button = event.currentTarget
    button.disabled = true
    button.textContent = 'Redirecting…'
    
    const apiUrl = new URL('/api/identity/url', window.location.origin)
    apiUrl.searchParams.set('program', this.programSlugValue)
    
    if (this.originalParamsValue) {
      apiUrl.searchParams.set('originalParams', this.originalParamsValue)
    }
    
    fetch(apiUrl.toString())
      .then(r => r.json().then(data => ({ ok: r.ok, data })))
      .then(({ok, data}) => {
        if(!ok || !data.url) { 
          throw new Error(data.error || 'Failed to generate OAuth URL')
        }
        window.location.href = data.url
      })
      .catch(err => {
        alert(err.message || 'Error starting verification')
        button.disabled = false
        button.textContent = 'Continue'
      })
  }
}
