Rails.application.config.middleware.use OmniAuth::Builder do
  provider :hack_club, ENV['IDENTITY_CLIENT_ID'], ENV['IDENTITY_CLIENT_SECRET'],
    setup: lambda { |env|
      request = Rack::Request.new(env)
      strategy = env['omniauth.strategy']
      strategy.options[:scope] = request.session['omniauth_scope'] || 'openid email name verification_status'
    }
end

# Allow GET requests to the request phase (needed for redirects and URL endpoint)
OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true

# Ensure correct callback URL behind reverse proxies
OmniAuth.config.full_host = ENV['NEXTAUTH_URL'] if ENV['NEXTAUTH_URL'].present?
