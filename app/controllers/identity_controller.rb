class IdentityController < ApplicationController
  require 'base64'
  require 'net/http'
  require 'securerandom'
  require 'uri'
  require Rails.root.join('app/services/user_journey_flow')
  require Rails.root.join('app/services/state_token')

  # Flow helper
  # Provides: UserJourneyFlow.generate_submit_id, build_state, encode_state, decode_state, build_form_url
  # See app/services/user_journey_flow.rb

  # GET /api/identity/url
  def url
  program = params[:program]
    original_params = params[:originalParams]

    unless program.present?
      return render json: { error: 'Program parameter required' }, status: :bad_request
    end

  # Enforce program exists and is active
  rec = Program.find_by(slug: program)
  return render json: { error: 'Program not found' }, status: :not_found unless rec
  return render json: { error: 'Program is inactive' }, status: :forbidden unless rec.active?

  # Base URL for redirect_uri; prefer request.base_url if NEXTAUTH_URL missing
  nextauth_url = ENV['NEXTAUTH_URL'].presence || request.base_url
    unless nextauth_url.present?
      Rails.logger.error('NEXTAUTH_URL environment variable is not set')
      return render json: { error: 'Server configuration error' }, status: :internal_server_error
    end

  submit_id = (session[:submit_id].presence || UserJourneyFlow.generate_submit_id).tap { |sid| session[:submit_id] = sid }
  state_hash = UserJourneyFlow.build_state(program: program, submit_id: submit_id, original_params: original_params)

  session[:state_nonce] = SecureRandom.hex(16)
  encoded_state = StateToken.generate(state_hash, nonce: session[:state_nonce])

    query = {
      client_id: ENV['IDENTITY_CLIENT_ID'],
      redirect_uri: join_url(nextauth_url, 'identity'),
      response_type: 'code',
      scope: 'basic_info',
      state: encoded_state
    }

    auth_url = URI(ENV['IDENTITY_URL'].to_s + '/oauth/authorize')
    auth_url.query = URI.encode_www_form(query)

    Rails.logger.info("Generated OAuth URL: #{auth_url}")
    render json: { url: auth_url.to_s }
  end

  # GET /identity/start?program=...&originalParams=...
  # Convenience endpoint that redirects the browser to the Identity Vault OAuth URL.
  def start
    program = params[:program]
    original_params = params[:originalParams]
    unless program.present?
      return redirect_to root_path, alert: 'Program parameter required'
    end

    # Enforce program exists and is active
    rec = Program.find_by(slug: program)
    unless rec&.active?
      return redirect_to root_path, alert: rec.nil? ? 'Program not found' : 'This program is closed.'
    end

  # Generate a unique Submit ID for this verification flow and signed state token
  # Reuse submit_id from session if already initialized on program page, else create a new one
  submit_id = (session[:submit_id].presence || UserJourneyFlow.generate_submit_id).tap { |sid| session[:submit_id] = sid }
  state_hash = UserJourneyFlow.build_state(program: program, submit_id: submit_id, original_params: original_params)
  session[:state_nonce] = SecureRandom.hex(16)
  encoded_state = StateToken.generate(state_hash, nonce: session[:state_nonce])

    # Log journey event for OAuth start (include submit_id)
    UserJourneyEvent.create!(
      event_type: 'oauth_start',
      program: program,
      request_ip: request.remote_ip,
      metadata: { user_agent: request.user_agent, original_params: original_params.presence, submit_id: submit_id }
    ) rescue nil

    nextauth_url = ENV['NEXTAUTH_URL'].presence || request.base_url
    query = {
      client_id: ENV['IDENTITY_CLIENT_ID'],
      redirect_uri: File.join(nextauth_url, 'identity'),
      response_type: 'code',
      scope: 'basic_info',
      state: encoded_state
    }
    auth_url = URI(ENV['IDENTITY_URL'].to_s + '/oauth/authorize')
    auth_url.query = URI.encode_www_form(query)
    redirect_to auth_url.to_s, allow_other_host: true
  end

  # GET /identity (OAuth callback)
  def callback
    code = params[:code]
    state = params[:state]

  unless code.present? && state.present?
      return redirect_to root_path, alert: 'Missing authorization code or state'
    end

    # Log journey event for OAuth callback (avoid logging raw params)
    UserJourneyEvent.create!(
      event_type: 'oauth_callback',
      request_ip: request.remote_ip,
      metadata: { user_agent: request.user_agent, has_code: code.present?, has_state: state.present? }
    ) rescue nil

  state_data = StateToken.verify(state)
  unless state_data
    return oauth_fail(reason: 'bad_state')
  end
  if session[:state_nonce].blank? || state_data['nonce'] != session[:state_nonce]
    return oauth_fail(reason: 'state_nonce_mismatch', extra_metadata: { stored_nonce_blank: session[:state_nonce].blank? })
  end
  session.delete(:state_nonce)
  submit_id = state_data['submit_id'] || session[:submit_id] || SecureRandom.uuid
  # Persist back into session so subsequent verify attempts from same browser keep association
  session[:submit_id] = submit_id

  token_uri = URI(ENV['IDENTITY_URL'].to_s + '/oauth/token')
    body = {
      code: code,
      client_id: ENV['IDENTITY_CLIENT_ID'],
      client_secret: ENV['IDENTITY_CLIENT_SECRET'],
  redirect_uri: join_url((ENV['NEXTAUTH_URL'].presence || request.base_url).to_s, 'identity'),
      grant_type: 'authorization_code'
    }

  http = Net::HTTP.new(token_uri.host, token_uri.port)
  http.use_ssl = token_uri.scheme == 'https'
  http.open_timeout = 3
  http.read_timeout = 5
    req = Net::HTTP::Post.new(token_uri, { 'Content-Type' => 'application/json' })
    req.body = body.to_json
    begin
      res = http.request(req)
    rescue => e
      return oauth_fail(reason: 'token_exchange_exception', extra_metadata: { error_class: e.class.name, error: e.message })
    end

    unless res.is_a?(Net::HTTPSuccess)
      return oauth_fail(reason: 'token_exchange_failed', extra_metadata: { http_code: res.code, body: truncate_body(res.body) })
    end

    token_data = JSON.parse(res.body)

    # Fetch user info
    me_uri = URI(ENV['IDENTITY_URL'].to_s + '/api/v1/me')
  http = Net::HTTP.new(me_uri.host, me_uri.port)
  http.use_ssl = me_uri.scheme == 'https'
  http.open_timeout = 3
  http.read_timeout = 5
    req = Net::HTTP::Get.new(me_uri)
    req['Authorization'] = "Bearer #{token_data['access_token']}"
    begin
      me_res = http.request(req)
    rescue => e
      return oauth_fail(reason: 'user_info_timeout', extra_metadata: { error_class: e.class.name, error: e.message })
    end

    unless me_res.is_a?(Net::HTTPSuccess)
      return oauth_fail(reason: 'user_info_fetch_failed', extra_metadata: { http_code: me_res.code, body: truncate_body(me_res.body) })
    end

  user_data = JSON.parse(me_res.body)['identity']
  user_data = IdentityNormalizer.normalize(user_data)

  if user_data['rejection_reason']
      return oauth_fail(
        reason: 'rejected',
        alert_message: 'Your submission got rejected! Go to identity.hackclub.com for more info.',
        program: state_data['program'],
        idv_rec: user_data['id'].to_s,
  email: user_data['email'],
        extra_metadata: { rejection_reason: user_data['rejection_reason'], verification_status: user_data['verification_status'], submit_id: submit_id }
      )
    end

  if user_data['verification_status'] == 'pending'
      return oauth_fail(
        reason: 'pending_verification',
        alert_message: 'Your identity verification is pending. Please wait for approval.',
        program: state_data['program'],
        idv_rec: user_data['id'].to_s,
  email: user_data['email'],
        extra_metadata: { verification_status: user_data['verification_status'], submit_id: submit_id }
      )
    end

  unless user_data['verification_status'] == 'verified'
      return oauth_fail(
        reason: 'missing_approved_verification',
        alert_message: "We couldn't find an approved verification yet. Visit identity.hackclub.com for more information.",
        program: state_data['program'],
        idv_rec: user_data['id'].to_s,
  email: user_data['email'],
        extra_metadata: { verification_status: user_data['verification_status'], ysws_eligible: user_data['ysws_eligible'], submit_id: submit_id }
      )
    end

  unless user_data['ysws_eligible']
      return oauth_fail(
        reason: 'over_18',
        alert_message: 'YSWS programs are for individuals 18 and under only.',
        program: state_data['program'],
        idv_rec: user_data['id'].to_s,
  email: user_data['email'],
        extra_metadata: { ysws_eligible: false, submit_id: submit_id }
      )
    end

    identity_key = user_data['id'].to_s

    # redirect to final form url with params
  program = Program.find_by(slug: state_data['program'])
  return redirect_to root_path, alert: 'Program not found' if program.nil?
  return redirect_to root_path, alert: 'This program is closed.' unless program.active?

  # Include program slug param on the form URL too
  final_url = UserJourneyFlow.build_form_url(
    program_config: {
      form_url: program.form_url,
      mappings: program.mappings.presence,
      scopes: program.scopes
    },
    identity_key: identity_key,
    user_data: user_data,
    state_data: state_data
  )
  uri_tmp = URI(final_url)
  q = URI.decode_www_form(uri_tmp.query.to_s)
  q << ['program', program.slug]
  uri_tmp.query = URI.encode_www_form(q)
  final_url = uri_tmp.to_s

    # Issue an authorized submit token tied to this identity and program.
    begin
      AuthorizedSubmitToken.create!(submit_id: submit_id, idv_rec: identity_key, program: program.slug, issued_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      # If it already exists, continue (idempotent on refresh)
    rescue => e
      Rails.logger.error("Failed to issue AuthorizedSubmitToken: #{e.class}: #{e.message}")
    end

    # Log success and redirect
    safe_create_journey_event(
      event_type: 'oauth_passed',
      program: state_data['program'],
      idv_rec: identity_key,
      email: user_data['email'],
      metadata: {
        first_name: user_data['first_name'],
        last_name: user_data['last_name'],
        slack_id: user_data['slack_id'].presence,
        verification_status: user_data['verification_status'],
        ysws_eligible: user_data['ysws_eligible'],
        original_params: state_data['originalParams'],
        submit_id: submit_id
      }.compact
    )

    safe_create_journey_event(
      event_type: 'redirect_to_form',
      program: state_data['program'],
      idv_rec: identity_key,
      email: user_data['email'],
      metadata: {
        final_url: final_url,
        first_name: user_data['first_name'],
        last_name: user_data['last_name'],
        slack_id: user_data['slack_id'].presence,
        submit_id: submit_id
      }.compact
    )

    redirect_to final_url, allow_other_host: true
  end

  private

  # Centralized failure handler for OAuth flow
  def oauth_fail(reason:, alert_message: 'Identity verification failed', program: nil, idv_rec: nil, email: nil, extra_metadata: {})
    base_metadata = { reason: reason }.merge(extra_metadata || {})
    Rails.logger.warn("OAuth failure: #{reason} metadata=#{base_metadata.inspect}")
    safe_create_journey_event(
      event_type: 'oauth_failed',
      program: program,
      idv_rec: idv_rec,
      email: email,
      metadata: base_metadata
    )
    redirect_to root_path, alert: alert_message
  end

  # Wrapper for creating journey events without swallowing errors silently
  def safe_create_journey_event(event_type:, program: nil, idv_rec: nil, email: nil, metadata: {})
    UserJourneyEvent.create!(
      event_type: event_type,
      program: program,
      idv_rec: idv_rec,
      email: email,
      request_ip: request.remote_ip,
      metadata: metadata.presence
    )
  rescue => e
    Rails.logger.error("UserJourneyEvent create failed (#{event_type}): #{e.class}: #{e.message}")
  end

  # Avoid logging excessively large bodies
  def truncate_body(body, limit = 500)
    return nil unless body
    body.length > limit ? body[0, limit] + '…(truncated)' : body
  end
end
