class OmniauthCallbacksController < ApplicationController
  # OmniAuth callbacks arrive as redirects from the external OAuth provider,
  # so they cannot carry a Rails CSRF token. This is standard for OmniAuth.
  # The OAuth state parameter (managed by OmniAuth) provides equivalent protection.
  skip_forgery_protection only: [:hack_club, :failure] # CodeQL: intentional

  # GET /auth/hack_club/callback
  def hack_club
    auth = request.env['omniauth.auth']
    context = session.delete('omniauth_context')

    unless auth && context
      return redirect_to root_path, alert: 'Authentication failed'
    end

    case context['flow']
    when 'user'
      handle_user_flow(auth, context)
    when 'admin'
      handle_admin_flow(auth)
    when 'popup'
      handle_popup_flow(auth, context)
    else
      redirect_to root_path, alert: 'Unknown authentication flow'
    end
  end

  # GET /auth/failure
  def failure
    message = params[:message] || 'Authentication failed'
    context = session.delete('omniauth_context')

    if context&.dig('flow') == 'popup'
      render 'popup/authorize/error', locals: { message: "Authentication failed: #{message}" }, layout: 'application'
    else
      redirect_to root_path, alert: "Authentication failed: #{message}"
    end
  end

  private

  def handle_user_flow(auth, context)
    user_data = extract_user_data(auth)
    program_slug = context['program']
    submit_id = context['submit_id']

    if user_data['rejection_reason']
      return oauth_fail(
        reason: 'rejected',
        alert_message: 'Your submission got rejected! Go to account.hackclub.com for more info.',
        program: program_slug,
        idv_rec: user_data['id'].to_s,
        email: user_data['email'],
        extra_metadata: { rejection_reason: user_data['rejection_reason'], verification_status: user_data['verification_status'], submit_id: submit_id }
      )
    end

    if user_data['verification_status'] == 'pending'
      return oauth_fail(
        reason: 'pending_verification',
        alert_message: 'Your identity verification is pending. Please wait for approval.',
        program: program_slug,
        idv_rec: user_data['id'].to_s,
        email: user_data['email'],
        extra_metadata: { verification_status: user_data['verification_status'], submit_id: submit_id }
      )
    end

    unless user_data['verification_status'] == 'verified'
      return oauth_fail(
        reason: 'missing_approved_verification',
        alert_message: "We couldn't find an approved verification yet. Visit account.hackclub.com for more information.",
        program: program_slug,
        idv_rec: user_data['id'].to_s,
        email: user_data['email'],
        extra_metadata: { verification_status: user_data['verification_status'], ysws_eligible: user_data['ysws_eligible'], submit_id: submit_id }
      )
    end

    unless user_data['ysws_eligible']
      return oauth_fail(
        reason: 'over_18',
        alert_message: 'YSWS programs are for individuals 18 and under only.',
        program: program_slug,
        idv_rec: user_data['id'].to_s,
        email: user_data['email'],
        extra_metadata: { ysws_eligible: false, submit_id: submit_id }
      )
    end

    identity_key = user_data['id'].to_s
    program = Program.find_by(slug: program_slug)
    return redirect_to root_path, alert: 'Program not found' if program.nil?
    return redirect_to root_path, alert: 'This program is closed.' unless program.active?

    final_url = UserJourneyFlow.build_form_url(
      program_config: {
        form_url: program.form_url,
        mappings: program.mappings.presence,
        scopes: program.scopes
      },
      identity_key: identity_key,
      user_data: user_data,
      state_data: { 'program' => program_slug, 'submit_id' => submit_id, 'originalParams' => context['original_params'] }
    )
    uri_tmp = URI(final_url)
    q = URI.decode_www_form(uri_tmp.query.to_s)
    q << ['program', program.slug]
    uri_tmp.query = URI.encode_www_form(q)
    final_url = uri_tmp.to_s

    begin
      AuthorizedSubmitToken.create!(submit_id: submit_id, idv_rec: identity_key, program: program.slug, issued_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      # Already exists, continue (idempotent on refresh)
    rescue => e
      Appsignal.send_error(e)
      Rails.logger.error("Failed to issue AuthorizedSubmitToken: #{e.class}: #{e.message}")
    end

    safe_create_journey_event(
      event_type: 'oauth_passed',
      program: program_slug,
      idv_rec: identity_key,
      email: user_data['email'],
      metadata: {
        first_name: user_data['first_name'],
        last_name: user_data['last_name'],
        slack_id: user_data['slack_id'].presence,
        verification_status: user_data['verification_status'],
        ysws_eligible: user_data['ysws_eligible'],
        original_params: context['original_params'],
        submit_id: submit_id
      }.compact
    )

    safe_create_journey_event(
      event_type: 'redirect_to_form',
      program: program_slug,
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

  def handle_admin_flow(auth)
    user_data = extract_user_data(auth)
    email = user_data['email']
    user = AdminUser.find_by(email: email)

    if user
      reset_session
      session[:admin_email] = email
      flash[:success] = 'Welcome back!'
      redirect_to user.ysws_author? ? admin_programs_path : admin_root_path
    else
      redirect_to root_path, alert: 'Unauthorized'
    end
  end

  def handle_popup_flow(auth, context)
    user_data = extract_user_data(auth)
    auth_id = context['auth_id']

    auth_request = AuthorizationRequest.find_by(auth_id: auth_id)
    unless auth_request&.pending?
      return render 'popup/authorize/error', locals: { message: 'Authorization request not found or expired' }, layout: 'application'
    end

    unless user_data['verification_status'] == 'verified'
      message = case user_data['verification_status']
      when 'pending'
        'Your identity verification is pending. Please wait for approval.'
      when 'rejected'
        'Your submission was rejected. Visit account.hackclub.com for more info.'
      else
        "We couldn't find an approved verification yet. Visit account.hackclub.com for more information."
      end
      return render 'popup/authorize/error', locals: { message: message }, layout: 'application'
    end

    unless user_data['ysws_eligible']
      return render 'popup/authorize/error', locals: { message: 'YSWS programs are for individuals 18 and under only' }, layout: 'application'
    end

    idv_rec = user_data['id'].to_s

    program_rec = auth_request.program_record
    filtered_identity = if program_rec
      allowed = program_rec.allowed_identity_fields
      identity_keys = allowed.map(&:to_s)
      user_data.slice(*identity_keys)
    else
      user_data.slice('id', 'verification_status', 'ysws_eligible', 'email')
    end

    auth_request.update!(identity_response: filtered_identity)
    auth_request.complete!(idv_rec)

    submit_id = UserJourneyFlow.generate_submit_id
    AuthorizedSubmitToken.create!(
      submit_id: submit_id,
      idv_rec: idv_rec,
      program: auth_request.program,
      issued_at: Time.current
    )

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
        slack_id: user_data['slack_id'].presence,
        verification_status: user_data['verification_status']
      }.compact
    ) rescue nil

    render 'popup/authorize/success', layout: 'application'
  rescue => e
    Appsignal.send_error(e)
    Rails.logger.error("Popup OAuth error: #{e.message}")
    UserJourneyEvent.create!(
      event_type: 'popup_oauth_error',
      program: auth_request&.program,
      request_ip: request.remote_ip,
      metadata: {
        auth_id: auth_id,
        error: e.message,
        error_class: e.class.name
      }
    ) rescue nil
    render 'popup/authorize/error', locals: { message: 'Authentication failed' }, layout: 'application'
  end

  def extract_user_data(auth)
    raw = auth.extra.raw_info
    granted_scopes = auth.extra.scopes
    # The API returns { "identity": { ... } } — extract the identity hash
    identity = raw.is_a?(Hash) && raw.key?('identity') ? raw['identity'] : raw
    Rails.logger.info("[OmniAuth] granted scopes: #{granted_scopes.inspect}")
    Rails.logger.info("[OmniAuth] identity keys: #{identity.keys.inspect rescue 'N/A'}")
    Rails.logger.info("[OmniAuth] birthday=#{identity['birthday'].inspect} addresses=#{identity['addresses'].inspect}")
    IdentityNormalizer.normalize(identity)
  end

  def oauth_fail(reason:, alert_message: 'Identity verification failed', program: nil, idv_rec: nil, email: nil, extra_metadata: {})
    Appsignal.send_error(RuntimeError.new("OAuth failure: #{reason} - #{alert_message}")) if alert_message.to_s.downcase.include?('failed')
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
    Appsignal.send_error(e)
    Rails.logger.error("UserJourneyEvent create failed (#{event_type}): #{e.class}: #{e.message}")
  end
end
