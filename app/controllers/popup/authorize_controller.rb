class Popup::AuthorizeController < ApplicationController
  require 'securerandom'
  require Rails.root.join('app/services/user_journey_flow')
  require Rails.root.join('app/services/state_token')

  # Use the program layout for the show screen so it matches the standard program page
  layout 'program', only: [:show]

  # GET /popup/authorize/:auth_id
  # Show the authorization popup page
  def show
    @auth_request = AuthorizationRequest.find_by(auth_id: params[:auth_id])
    
    unless @auth_request&.pending?
      return render :expired, layout: 'application'
    end

  # Do not auto-expire here; allow pending requests to proceed immediately.

    @program = Program.find_by(slug: @auth_request.program)
    
    unless @program&.active?
      return render :error, locals: { message: 'Program not found or inactive' }, layout: 'application'
    end

    # Generate OAuth URL for this specific authorization request
    submit_id = UserJourneyFlow.generate_submit_id
    state_hash = UserJourneyFlow.build_state(
      program: @program.slug, 
      submit_id: submit_id, 
      auth_id: @auth_request.auth_id  # Include auth_id in state
    )
    
    session[:state_nonce] = SecureRandom.hex(16)
    session[:auth_id] = @auth_request.auth_id  # Track this authorization session
    encoded_state = StateToken.generate(state_hash, nonce: session[:state_nonce])

    nextauth_url = ENV['NEXTAUTH_URL'].presence || request.base_url
    query = {
      client_id: ENV['IDENTITY_CLIENT_ID'],
      redirect_uri: join_url(nextauth_url, 'popup/authorize/callback'),
      response_type: 'code',
      scope: 'basic_info',
      state: encoded_state
    }

    auth_url = URI(ENV['IDENTITY_URL'].to_s + '/oauth/authorize')
    auth_url.query = URI.encode_www_form(query)
    
    @oauth_url = auth_url.to_s
  end

  # GET /popup/authorize/callback (OAuth callback for popup flow)
  def callback
    code = params[:code]
    state = params[:state]

    unless code.present? && state.present?
      return render :error, locals: { message: 'Missing authorization code or state' }, layout: 'application'
    end

    state_data = StateToken.verify(state)
    unless state_data
      return render :error, locals: { message: 'Invalid state token' }, layout: 'application'
    end

    unless session[:state_nonce].present? && state_data['nonce'] == session[:state_nonce]
      return render :error, locals: { message: 'State verification failed' }, layout: 'application'
    end

    auth_id = state_data['auth_id'] || session[:auth_id]
    unless auth_id
      return render :error, locals: { message: 'Authorization ID missing' }, layout: 'application'
    end

    auth_request = AuthorizationRequest.find_by(auth_id: auth_id)
    unless auth_request&.pending?
      return render :error, locals: { message: 'Authorization request not found or expired' }, layout: 'application'
    end

    # Exchange code for token and get user info (similar to identity_controller.rb)
    begin
      user_data = exchange_oauth_code_for_user_data(code)

      # Verify user meets requirements
      unless user_data['verification_status'] == 'verified'
        message = case user_data['verification_status']
        when 'pending'
          'Your identity verification is pending. Please wait for approval.'
        when 'rejected'
          'Your submission was rejected. Visit identity.hackclub.com for more info.'
        else
          "We couldn't find an approved verification yet. Visit identity.hackclub.com for more information."
        end
        return render :error, locals: { message: message }, layout: 'application'
      end

      unless user_data['ysws_eligible']
        return render :error, locals: { message: 'YSWS programs are for individuals 18 and under only' }, layout: 'application'
      end

      # Complete the authorization request
      idv_rec = user_data['id'].to_s
      
      # Restrict identity_response fields by program scopes (if provided), mirroring VerifyController
      program_rec = auth_request.program_record
      filtered_identity = if program_rec
        allowed = program_rec.allowed_identity_fields
        # Use 'email' across the board
        identity_keys = allowed.map(&:to_s)
        user_data.slice(*identity_keys)
      else
        user_data.slice('id', 'verification_status', 'ysws_eligible', 'email')
      end

      auth_request.update!(identity_response: filtered_identity)
      auth_request.complete!(idv_rec)

      # Issue the submit token for later verification
      submit_id = UserJourneyFlow.generate_submit_id
      AuthorizedSubmitToken.create!(
        submit_id: submit_id, 
        idv_rec: idv_rec, 
        program: auth_request.program, 
        issued_at: Time.current
      )

      # Log the successful authorization
      UserJourneyEvent.create!(
        event_type: 'popup_oauth_success',
        program: auth_request.program,
        idv_rec: idv_rec,
  email: user_data['email'],
        request_ip: request.remote_ip,
        metadata: { 
          auth_id: auth_id,
          submit_id: submit_id,
          first_name: user_data['first_name'], 
          last_name: user_data['last_name'],
          verification_status: user_data['verification_status']
        }
      ) rescue nil

      # Clear session data
      session.delete(:state_nonce)
      session.delete(:auth_id)
      
      render :success, layout: 'application'
      
    rescue => e
      Rails.logger.error("Popup OAuth error: #{e.message}")
      UserJourneyEvent.create!(
        event_type: 'popup_oauth_error',
        program: auth_request.program,
        request_ip: request.remote_ip,
        metadata: { 
          auth_id: auth_id,
          error: e.message,
          error_class: e.class.name
        }
      ) rescue nil
      
      render :error, locals: { message: 'Authentication failed' }, layout: 'application'
    end
  end

  private

  def exchange_oauth_code_for_user_data(code)
    # Token exchange
    token_uri = URI(ENV['IDENTITY_URL'].to_s + '/oauth/token')
    body = {
      code: code,
      client_id: ENV['IDENTITY_CLIENT_ID'],
      client_secret: ENV['IDENTITY_CLIENT_SECRET'],
  redirect_uri: join_url((ENV['NEXTAUTH_URL'].presence || request.base_url).to_s, 'popup/authorize/callback'),
      grant_type: 'authorization_code'
    }

    http = Net::HTTP.new(token_uri.host, token_uri.port)
    http.use_ssl = token_uri.scheme == 'https'
    http.open_timeout = 3
    http.read_timeout = 5
    req = Net::HTTP::Post.new(token_uri, { 'Content-Type' => 'application/json' })
    req.body = body.to_json
    
    res = http.request(req)
    raise "Token exchange failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    
    token_data = JSON.parse(res.body)

    # Fetch user info
    me_uri = URI(ENV['IDENTITY_URL'].to_s + '/api/v1/me')
    http = Net::HTTP.new(me_uri.host, me_uri.port)
    http.use_ssl = me_uri.scheme == 'https'
    http.open_timeout = 3
    http.read_timeout = 5
    req = Net::HTTP::Get.new(me_uri)
    req['Authorization'] = "Bearer #{token_data['access_token']}"
    
    me_res = http.request(req)
    raise "User info fetch failed: #{me_res.code}" unless me_res.is_a?(Net::HTTPSuccess)

    user_data = JSON.parse(me_res.body)['identity']
    IdentityNormalizer.normalize(user_data)
  end
end
