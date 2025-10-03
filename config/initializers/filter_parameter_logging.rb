# Be sure to restart your server when you modify this file.

# Configure parameters to be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password,
  :authorization,
  :access_token,
  :token,
  :client_secret,
  :email,
  :first_name,
  :last_name,
  :idv_rec
]
