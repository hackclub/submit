require_relative "boot"

require "rails/all"

# Load environment variables from .env in development and test (dotenv-rails)
begin
  require 'dotenv'
  Dotenv.load if ENV["RAILS_ENV"].nil? || %w[development test].include?(ENV["RAILS_ENV"]) || %w[development test].include?(ENV["RACK_ENV"]) 
rescue LoadError
  # dotenv not available in production, that's fine
end

Bundler.require(*Rails.groups)

module SubmitRuby
  class Application < Rails::Application
    config.load_defaults 7.1

    # Basic, minimal stack
    config.generators.system_tests = nil

  # Ensure services are autoloaded/eager loaded (UserJourneyFlow, etc.)
  config.autoload_paths << Rails.root.join('app', 'services')
  config.eager_load_paths << Rails.root.join('app', 'services')
  end
end
