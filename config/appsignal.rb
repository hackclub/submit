Appsignal.configure do |config|
  config.activate_if_environment(:production)
  config.push_api_key = Rails.application.credentials.dig(:appsignal, :push_api_key)
end
