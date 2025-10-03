# Bound request time to protect against slowloris / backend slowness
# rack-timeout 0.7.x uses middleware options instead of class-level setters.
service_timeout = Integer(ENV.fetch('REQUEST_TIMEOUT', '10')) # seconds

# You can also set WAIT and OVERTIME via env (see rack-timeout README):
# RACK_TIMEOUT_WAIT_TIMEOUT, RACK_TIMEOUT_WAIT_OVERTIME, etc.

Rails.application.config.middleware.insert_before(
	Rack::Runtime,
	Rack::Timeout,
	service_timeout: service_timeout
)
