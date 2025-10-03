class Api::AuthorizeController < ApplicationController
  before_action :authenticate_api_key
  skip_before_action :verify_authenticity_token

  # POST /api/authorize
  # Creates a new authorization request and returns a popup URL
  def create
    auth_id = SecureRandom.uuid
    
    auth_request = AuthorizationRequest.create!(
      auth_id: auth_id,
      program: @program.slug
    )

    # Generate popup URL similar to existing identity flow
    popup_url = generate_popup_url(auth_id)
    auth_request.update!(popup_url: popup_url)

    render json: {
      auth_id: auth_id,
      popup_url: popup_url,
      status: 'pending',
      expires_at: 15.minutes.from_now
    }
  end

  # GET /api/authorize/:auth_id/status
  # Check the status of an authorization request
  def status
    auth_request = AuthorizationRequest.find_by!(auth_id: params[:auth_id])
    
    # Expire old requests
    auth_request.expire! if auth_request.created_at < 15.minutes.ago
    
    # Program isolation: API key must belong to the same program
    if @program.slug != auth_request.program
      return render json: { error: 'Not allowed' }, status: :forbidden
    end

    # If authorization was completed and already consumed, block further reads
    if auth_request.completed? && auth_request.consumed_at.present?
      return render json: { error: 'Not allowed' }, status: :forbidden
    end

    response_data = {
      auth_id: auth_request.auth_id,
      status: auth_request.status,
      created_at: auth_request.created_at,
      program: auth_request.program
    }

    http_status = :ok
    if auth_request.completed?
      response_data.merge!(
        idv_rec: auth_request.idv_rec,
        completed_at: auth_request.completed_at,
        verified: true,
        identity_response: auth_request.identity_response
      )
    elsif auth_request.status == 'expired'
      response_data.merge!(verified: false, error: 'Authorization expired', identity_response: nil)
    elsif auth_request.status == 'failed'
      response_data.merge!(verified: false, error: 'Authorization failed', identity_response: nil)
    else
      # pending
      response_data.merge!(verified: false, identity_response: nil)
      http_status = :accepted
    end

    # If we responded with a completed status, mark consumed_at to prevent future reads
    if auth_request.completed?
      auth_request.update_columns(consumed_at: Time.current)
    end

    render json: response_data, status: http_status
  end

  private

  def authenticate_api_key
    api_key = request.headers['Authorization']&.sub(/\ABearer /, '')
    
    unless api_key
      return render json: { error: 'API key required' }, status: :unauthorized
    end

    @program = Program.find_by(api_key: api_key)
    
    unless @program&.active?
      return render json: { error: 'Invalid or inactive API key' }, status: :unauthorized
    end
  end

  def generate_popup_url(auth_id)
  base_url = ENV['NEXTAUTH_URL'].presence || request.base_url
  join_url(base_url, 'popup/authorize', auth_id)
  end
end
