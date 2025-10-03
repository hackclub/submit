// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "controllers"

// Notify HelpScout Beacon of Turbo page navigations (for URL-based suggestions/messages)
document.addEventListener('turbo:load', () => {
	if (window.Beacon) {
		try {
			window.Beacon('event', {
				type: 'page-viewed',
				url: document.location.href,
				title: document.title,
			})
			// Refresh suggestions that depend on current URL
			window.Beacon('suggest')
		} catch (e) {
			// no-op
		}
	}
})
