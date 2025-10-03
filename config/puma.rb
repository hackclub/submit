max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Bind explicitly to 0.0.0.0 so traffic from the container network is accepted
bind "tcp://0.0.0.0:#{ENV.fetch("PORT") { 80 }}"
environment ENV.fetch("RAILS_ENV") { "development" }
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Use more workers in production by default; single process in development
rails_env = ENV.fetch("RAILS_ENV") { "development" }
workers_count = if rails_env == "production"
	Integer(ENV.fetch("WEB_CONCURRENCY", "2"))
else
	Integer(ENV.fetch("WEB_CONCURRENCY", "0"))
end
workers workers_count


preload_app!

# Reconnect Active Record in worker processes
on_worker_boot do
	ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

plugin :tmp_restart
