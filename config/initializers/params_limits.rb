# Limit incoming request parameters to prevent resource exhaustion
Rails.application.config.action_dispatch.perform_deep_munge = false

# Rack 3 removed Rack::Utils.key_space_limit. Configure the default query parser instead.
# Defaults: Rack is ~1000; we set somewhat lower, override via env if needed.
max_params = Integer(ENV.fetch('MAX_PARAMS', '500'))
param_depth = Integer(ENV.fetch('MAX_PARAM_DEPTH', '100'))

if defined?(Rack::QueryParser) && Rack::Utils.respond_to?(:default_query_parser=)
	# Apply limits to both query string and urlencoded body params
	# Rack 3.2 signature: (params_class, param_depth_limit, bytesize_limit:, params_limit:)
	Rack::Utils.default_query_parser = Rack::QueryParser.new(
		Rack::QueryParser::Params,
		param_depth,
		params_limit: max_params
	)
else
	# Older Rack versions or unexpected environment; skip rather than crash
	Rails.logger.warn("Rack::QueryParser not available; skipping parameter limits configuration")
end

# Limit multipart body size via Rack tempfiles; for non-multipart, rely on reverse proxy limits
# You should also enforce body size at the proxy (nginx/elb) for strong guarantees.
