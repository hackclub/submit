Rack::Attack.cache.store = Rails.cache

class Rack::Attack
  # Safelist health checks and local dev
  safelist('healthz-and-local') do |req|
    req.path == '/healthz' || %w[127.0.0.1 ::1].include?(req.ip)
  end

  # Ignore static assets and precompiled files
  safelist('assets') do |req|
    req.path.start_with?('/assets/', '/favicon', '/robots.txt')
  end

  # Global throttles per-IP (lightweight baseline)
  throttle('req/ip/minute', limit: (ENV.fetch('RATE_LIMIT_PER_MINUTE', '100').to_i), period: 1.minute) do |req|
    next if req.get_header('HTTP_CF_CONNECTING_IP') # if using CDN that handles rate limits
    next if req.path == '/healthz' || req.path.start_with?('/assets/')
    req.ip
  end

  throttle('req/ip/burst', limit: (ENV.fetch('RATE_LIMIT_BURST', '20').to_i), period: 10.seconds) do |req|
    next if req.path == '/healthz' || req.path.start_with?('/assets/')
    req.ip
  end

  # Identity/OAuth endpoints (tighter)
  throttle('oauth/ip', limit: 20, period: 1.minute) do |req|
    if req.get? && (req.path == '/api/identity/url' || req.path == '/identity/start' || req.path == '/identity')
      req.ip
    end
  end

  # Verify endpoint: throttle per IP and per email (if present)
  throttle('verify/ip', limit: 30, period: 1.minute) do |req|
    req.ip if req.get? && req.path == '/api/verify'
  end

  throttle('verify/email', limit: 10, period: 1.minute) do |req|
    if req.get? && req.path == '/api/verify'
      begin
        email = Rack::Request.new(req.env).params['email'].to_s.downcase.strip
        email.presence
      rescue => _
        nil
      end
    end
  end

  # Admin login flows (OAuth begin/callback)
  throttle('admin_login/ip', limit: 10, period: 1.minute) do |req|
    if req.get? && (req.path == '/admin/login' || req.path == '/admin/callback')
      req.ip
    end
  end

  # Return JSON for throttled requests (Rack::Attack 6+ API)
  Rack::Attack.throttled_responder = lambda do |req|
    now = Time.now.utc
    match = req.env['rack.attack.match_data'] || {}
    retry_after = match[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s,
        'Cache-Control' => 'no-store'
      },
      [ { error: 'rate_limited', at: now.iso8601 }.to_json ]
    ]
  end
end

Rails.application.config.middleware.use Rack::Attack
