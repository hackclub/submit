class HealthController < ActionController::Base
  # Fast and simple health check; avoid DB/external calls.
  skip_forgery_protection

  def show
    response.set_header('Cache-Control', 'no-store')
    render plain: 'ok', status: :ok
  end
end
