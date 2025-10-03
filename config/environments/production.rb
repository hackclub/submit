Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  
  # Use environment variable for secret key base
  config.secret_key_base = ENV['SECRET_KEY_BASE']
  # Cache store (used by Rack::Attack counters); replace with Redis in clustered envs
  config.cache_store = :memory_store, { size: 64.megabytes }
  # Enforce HTTPS and secure cookies
  config.force_ssl = true
  # Allow HTTP for container-internal healthcheck
  config.ssl_options = {
    hsts: { expires: 1.year, subdomains: true },
    redirect: { exclude: ->(request) { request.path == "/healthz" } }
  }
  # Restrict allowed hosts via ENV (set APP_HOST, APP_HOST_ALT as needed)
  if ENV['APP_HOST'].present?
    config.hosts << ENV['APP_HOST']
  end
  if ENV['APP_HOST_ALT'].present?
    config.hosts << ENV['APP_HOST_ALT']
  end

  # Allow /healthz to bypass host authorization (used by container-local healthchecks)
  config.host_authorization = { exclude: ->(request) { request.path == "/healthz" } }

  # Security headers
  config.action_dispatch.default_headers.merge!({
    'X-Frame-Options' => 'DENY',
    'X-Content-Type-Options' => 'nosniff',
    'Referrer-Policy' => 'strict-origin-when-cross-origin'
  })
end
