module Api
  class VerifyController < ApplicationController
    require 'net/http'

    # GET /api/verify?idv_rec=...&first_name=...&last_name=...&email=...
    def index
      # idv_rec may come in as "IDENTITY:SUBMIT" combined string; split when present
      idv_rec_raw = params[:idv_rec].to_s
      idv_rec, submit_id = if idv_rec_raw.include?(':')
        parts = idv_rec_raw.split(':', 2)
        [parts[0], parts[1]]
      else
        [idv_rec_raw.presence, params[:submit_id].presence]
      end

      # Enforce one-time use of submit_id (token). If the token was already used,
      # short-circuit with 410 Gone. We consider any prior attempt a use, even if
      # it resulted in an error, to prevent replay and data harvesting.
      if submit_id.present? && VerificationAttempt.exists?(submit_id: submit_id)
        UserJourneyEvent.create!(
          event_type: 'verification_attempt_reuse',
          program: params[:program].presence,
          idv_rec: idv_rec,
          email: params[:email].to_s.strip.downcase,
          request_ip: request.remote_ip,
          metadata: { error: 'submit_id_reused', submit_id: submit_id }
        ) rescue nil
        return render json: { verified: false, error: 'Submit token already used', identity_response: nil }, status: :gone
      end

      first_name = params[:first_name].to_s.strip
      last_name  = params[:last_name].to_s.strip
      email      = params[:email].to_s.strip.downcase
      program_slug = params[:program].presence
      program_rec  = Program.find_by(slug: program_slug) if program_slug
      if program_slug
        if program_rec.nil?
          return render json: { verified: false, error: 'Program not found', identity_response: nil }, status: :not_found
        elsif !program_rec.active?
          return render json: { verified: false, error: 'Program is inactive', identity_response: nil }, status: :forbidden
        end
      end

      # Require an OAuth-issued authorized token bound to this idv_rec (and program when provided)
      if submit_id.blank?
        UserJourneyEvent.create!(
          event_type: 'unauthorized_submit_id',
          program: program_slug,
          idv_rec: idv_rec,
          email: email,
          request_ip: request.remote_ip,
          metadata: { error: 'missing_submit_id' }
        ) rescue nil
        return render json: { verified: false, error: 'Submit token required', identity_response: nil }, status: :forbidden
      end
      authorized_token = AuthorizedSubmitToken.find_by(submit_id: submit_id)
      if authorized_token.nil? || authorized_token.idv_rec.to_s != idv_rec.to_s || (program_slug.present? && authorized_token.program.present? && authorized_token.program != program_slug)
        UserJourneyEvent.create!(
          event_type: 'unauthorized_submit_id',
          program: program_slug,
          idv_rec: idv_rec,
          email: email,
          request_ip: request.remote_ip,
          metadata: { error: 'submit_id_not_authorized', submit_id: submit_id, token_program: authorized_token&.program }
        ) rescue nil
        return render json: { verified: false, error: 'Submit token not authorized for this identity', identity_response: nil }, status: :forbidden
      end

      unless idv_rec.present? && first_name.present? && last_name.present? && email.present?
        # Do NOT create a VerificationAttempt record when the request is simply a program page view
        # (e.g., embedding or pre-flight call without required identity params). This prevents
        # "empty" verification sessions from showing up in the admin UI.
        UserJourneyEvent.create!(
          event_type: 'verification_attempt',
          program: program_slug,
          idv_rec: idv_rec,
          email: email,
          request_ip: request.remote_ip,
          metadata: { error: 'missing_params', submit_id: submit_id }
        ) rescue nil
        return render json: { verified: false, error: 'Missing required parameters: idv_rec, first_name, last_name, email' }, status: :bad_request
      end

      unless ENV['IDENTITY_URL'].present? && ENV['IDENTITY_PROGRAM_KEY'].present?
        Rails.logger.error('Missing Identity Vault configuration')
        attempt = create_attempt_safely!(
          idv_rec: idv_rec,
          first_name: first_name,
          last_name: last_name,
          email: email,
          program: program_slug,
          submit_id: submit_id,
          verified: false,
          identity_response: nil,
          ip: request.remote_ip,
          verification_status: nil
        )
        UserJourneyEvent.create!(
          event_type: 'verification_attempt',
          program: program_slug,
          idv_rec: idv_rec,
          email: email,
          request_ip: request.remote_ip,
          verification_attempt_id: attempt&.id,
          metadata: { error: 'server_config', submit_id: submit_id }
        ) rescue nil
        return render json: { verified: false, error: 'Server configuration error' }, status: :internal_server_error
      end

      uri = URI(File.join(ENV['IDENTITY_URL'], "/api/v1/identities/#{idv_rec}"))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 3
      http.read_timeout = 5

      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{ENV['IDENTITY_PROGRAM_KEY']}"
      req['Accept'] = 'application/json'

      begin
        res = http.request(req)
      rescue => e
        Rails.logger.error("Identity API error: #{e.class}: #{e.message}")
        attempt = create_attempt_safely!(idv_rec: idv_rec, first_name: first_name, last_name: last_name, email: email, program: program_slug, submit_id: submit_id, verified: false, identity_response: nil, ip: request.remote_ip)
        UserJourneyEvent.create!(event_type: 'verification_attempt', program: program_slug, idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { error: 'fetch_timeout', submit_id: submit_id }) rescue nil
        return render json: { verified: false, error: 'Failed to fetch user data', identity_response: nil }, status: :internal_server_error
      end

      unless res.is_a?(Net::HTTPSuccess)
        if res.code.to_i == 404
          attempt = create_attempt_safely!(idv_rec: idv_rec, first_name: first_name, last_name: last_name, email: email, program: program_slug, submit_id: submit_id, verified: false, identity_response: nil, ip: request.remote_ip)
          UserJourneyEvent.create!(event_type: 'verification_attempt', program: program_slug, idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { error: '404', submit_id: submit_id }) rescue nil
          return render json: { verified: false, identity_response: nil }
        else
          Rails.logger.error("User fetch failed: #{res.code} - #{res.body}")
          attempt = create_attempt_safely!(idv_rec: idv_rec, first_name: first_name, last_name: last_name, email: email, program: program_slug, submit_id: submit_id, verified: false, identity_response: nil, ip: request.remote_ip)
          UserJourneyEvent.create!(event_type: 'verification_attempt', program: program_slug, idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { error: 'fetch_failed', code: res.code, submit_id: submit_id }) rescue nil
          return render json: { verified: false, error: 'Failed to fetch user data', identity_response: nil }, status: :internal_server_error
        end
      end

      begin
        body = JSON.parse(res.body)
        user_data = body['identity']
        user_data = IdentityNormalizer.normalize(user_data)
      rescue => e
        Rails.logger.error("Invalid JSON from identity API: #{e.message}")
        attempt = create_attempt_safely!(
          idv_rec: idv_rec,
          first_name: first_name,
          last_name: last_name,
          email: email,
          program: program_slug,
          submit_id: submit_id,
          verified: false,
          identity_response: nil,
          ip: request.remote_ip,
          verification_status: nil
        )
        UserJourneyEvent.create!(event_type: 'verification_attempt', program: program_slug, idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { error: 'invalid_json', submit_id: submit_id }) rescue nil
        return render json: { verified: false, error: 'Identity data not found in response', identity_response: nil }
      end

      if user_data.nil?
        attempt = create_attempt_safely!(idv_rec: idv_rec, first_name: first_name, last_name: last_name, email: email, program: program_slug, submit_id: submit_id, verified: false, identity_response: nil, ip: request.remote_ip)
        UserJourneyEvent.create!(event_type: 'verification_attempt', program: program_slug, idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { error: 'no_identity_data', submit_id: submit_id }) rescue nil
        return render json: { verified: false, error: 'Identity data not found in response', identity_response: nil }
      end

      if user_data['verification_status'] != 'verified' || user_data['rejection_reason'].present?
        message = if user_data['rejection_reason'].present?
          'Your submission was rejected. Visit identity.hackclub.com for more info.'
        elsif user_data['verification_status'] == 'pending'
          'Your identity verification is pending. Please wait for approval.'
        else
          "We couldn't find an approved verification yet. Check identity.hackclub.com for more information."
        end

        attempt = create_attempt_safely!(
          idv_rec: idv_rec,
          first_name: first_name,
          last_name: last_name,
          email: email,
          program: program_slug,
          submit_id: submit_id,
          verified: false,
          identity_response: user_data,
          ip: request.remote_ip,
          verification_status: user_data['verification_status'],
          rejection_reason: user_data['rejection_reason'],
          ysws_eligible: user_data['ysws_eligible']
        )
        UserJourneyEvent.create!(
          event_type: 'verification_attempt',
          program: program_slug,
          idv_rec: idv_rec,
          email: email,
          request_ip: request.remote_ip,
          verification_attempt_id: attempt&.id,
          metadata: { error: 'not_verified', status: user_data['verification_status'], rejection_reason: user_data['rejection_reason'], submit_id: submit_id }
        ) rescue nil
        return render json: { verified: false, error: message, identity_response: user_data }
      end

      if user_data['verification_status'] == 'verified' && !user_data['ysws_eligible']
        attempt = create_attempt_safely!(
          idv_rec: idv_rec,
          first_name: first_name,
          last_name: last_name,
          email: email,
          program: program_slug,
          submit_id: submit_id,
          verified: false,
          identity_response: user_data,
          ip: request.remote_ip,
          verification_status: user_data['verification_status'],
          ysws_eligible: user_data['ysws_eligible']
        )
        UserJourneyEvent.create!(
          event_type: 'verification_attempt',
          program: program_slug,
          idv_rec: idv_rec,
          email: email,
          request_ip: request.remote_ip,
          verification_attempt_id: attempt&.id,
          metadata: { error: 'ysws_ineligible', submit_id: submit_id }
        ) rescue nil
        return render json: { verified: false, error: 'YSWS programs are for individuals 18 and under only', identity_response: user_data }
      end

      first_name_match = user_data['first_name'].to_s.strip == first_name
      last_name_match  = user_data['last_name'].to_s.strip  == last_name
  email_match      = user_data['email'].to_s.strip.downcase == email
      all_match        = first_name_match && last_name_match && email_match

      Rails.logger.info({ event: 'verification_attempt', idv_rec: idv_rec, verified: all_match, timestamp: Time.now.utc.iso8601 }.to_json)

      # Restrict identity_response fields by program scopes (if provided)
      filtered_identity = if program_rec
        allowed = program_rec.allowed_identity_fields
        identity_keys = allowed.map(&:to_s)
        user_data.slice(*identity_keys)
      else
        # Default minimal fields when no program scopes are defined
        user_data.slice('id', 'verification_status', 'ysws_eligible', 'email')
      end

      attempt = create_attempt_safely!(
        idv_rec: idv_rec,
        first_name: first_name,
        last_name: last_name,
        email: email,
        program: program_rec&.slug || program_slug,
        submit_id: submit_id,
        verified: all_match,
        identity_response: filtered_identity,
        ip: request.remote_ip,
        verification_status: user_data['verification_status'],
        ysws_eligible: user_data['ysws_eligible']
      )
      UserJourneyEvent.create!(event_type: 'verification_attempt', program: (program_rec&.slug || program_slug), idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { verified: all_match, submit_id: submit_id }) rescue nil
      begin
        authorized_token.consume!
      rescue => _
      end

      render json: { verified: all_match, identity_response: filtered_identity }
    rescue ActiveRecord::RecordNotUnique
      # Duplicate submit_id indicates token reuse race condition
      UserJourneyEvent.create!(
        event_type: 'verification_attempt_reuse',
        program: params[:program].presence,
        idv_rec: params[:idv_rec].to_s.split(':', 2)[0],
        email: params[:email].to_s.strip.downcase,
        request_ip: request.remote_ip,
        metadata: { error: 'submit_id_reused', submit_id: params[:submit_id].presence || params[:idv_rec].to_s.split(':', 2)[1] }
      ) rescue nil
      render json: { verified: false, error: 'Submit token already used', identity_response: nil }, status: :gone
    rescue => e
      Rails.logger.error("Verification error: #{e.message}")
      attempt = create_attempt_safely!(idv_rec: idv_rec, first_name: first_name, last_name: last_name, email: email, program: (program_rec&.slug || program_slug), submit_id: submit_id, verified: false, identity_response: nil, ip: request.remote_ip)
      UserJourneyEvent.create!(event_type: 'verification_attempt', program: (program_rec&.slug || program_slug), idv_rec: idv_rec, email: email, request_ip: request.remote_ip, verification_attempt_id: attempt&.id, metadata: { error: 'exception', message: e.message, submit_id: submit_id }) rescue nil
      render json: { verified: false, error: 'Internal server error', identity_response: nil }, status: :internal_server_error
    end

    private

    # Create attempt, but don't swallow unique constraint errors on submit_id.
    # Return nil on other failures to preserve existing behavior.
    def create_attempt_safely!(attrs)
      VerificationAttempt.create!(attrs)
    rescue ActiveRecord::RecordNotUnique
      raise
    rescue => _
      nil
    end
  end
end
