import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["picker", "text"]

  connect() {
    this.pickerTargets.forEach((picker, i) => {
      const text = this.textTargets[i]
      if (picker && text) {
        picker.addEventListener('input', e => {
          text.value = e.target.value.replace('#', '').toLowerCase()
        })
        text.addEventListener('input', e => {
          // Remove any #, non-hex chars, and force lowercase, preserving cursor position
          const input = e.target;
          const start = input.selectionStart;
          const end = input.selectionEnd;
          let v = input.value.replace(/[^A-Fa-f0-9]/gi, '').slice(0,6).toLowerCase();
          // Only update if value actually changes to avoid cursor jump
          if (input.value !== v) {
            input.value = v;
            // Try to restore cursor position
            input.setSelectionRange(Math.min(start, v.length), Math.min(end, v.length));
          }
          if (v.length === 6) picker.value = '#' + v;
        })
        // Initial sync (on load)
        let v = text.value.replace(/[^A-Fa-f0-9]/gi, '').slice(0,6).toLowerCase();
        if (v.length === 6) {
          picker.value = '#' + v;
          text.value = v;
        } else if (picker.value) {
          text.value = picker.value.replace('#', '').toLowerCase();
        }
      }
    })
  }
}
