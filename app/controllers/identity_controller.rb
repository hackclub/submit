class IdentityController < ApplicationController
  require Rails.root.join('app/services/user_journey_flow')

  # GET /api/identity/url
  def url
    program = params[:program]
    original_params = params[:originalParams]

    unless program.present?
      return render json: { error: 'Program parameter required' }, status: :bad_request
    end

    rec = Program.find_by(slug: program)
    return render json: { error: 'Program not found' }, status: :not_found unless rec
    return render json: { error: 'Program is inactive' }, status: :forbidden unless rec.active?

    submit_id = (session[:submit_id].presence || UserJourneyFlow.generate_submit_id).tap { |sid| session[:submit_id] = sid }

    session['omniauth_scope'] = rec.oauth_scopes
    session['omniauth_context'] = {
      'flow' => 'user',
      'program' => program,
      'submit_id' => submit_id,
      'original_params' => original_params.presence
    }

    nextauth_url = ENV['NEXTAUTH_URL'].presence || request.base_url
    auth_url = "#{nextauth_url.to_s.chomp('/')}/auth/hack_club"

    Rails.logger.info("Generated OAuth URL: #{auth_url}")
    render json: { url: auth_url }
  end

  # GET /identity/start?program=...&originalParams=...
  def start
    program = params[:program]
    original_params = params[:originalParams]
    unless program.present?
      return redirect_to root_path, alert: 'Program parameter required'
    end

    rec = Program.find_by(slug: program)
    unless rec&.active?
      return redirect_to root_path, alert: rec.nil? ? 'Program not found' : 'This program is closed.'
    end

    submit_id = (session[:submit_id].presence || UserJourneyFlow.generate_submit_id).tap { |sid| session[:submit_id] = sid }

    UserJourneyEvent.create!(
      event_type: 'oauth_start',
      program: program,
      request_ip: request.remote_ip,
      metadata: { user_agent: request.user_agent, original_params: original_params.presence, submit_id: submit_id }
    ) rescue nil

    session['omniauth_scope'] = rec.oauth_scopes
    session['omniauth_context'] = {
      'flow' => 'user',
      'program' => program,
      'submit_id' => submit_id,
      'original_params' => original_params.presence
    }

    redirect_to '/auth/hack_club'
  end
end
