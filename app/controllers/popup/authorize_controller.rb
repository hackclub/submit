class Popup::AuthorizeController < ApplicationController
  require Rails.root.join('app/services/user_journey_flow')

  layout 'program', only: [:show]

  # GET /popup/authorize/:auth_id
  def show
    @auth_request = AuthorizationRequest.find_by(auth_id: params[:auth_id])

    unless @auth_request&.pending?
      return render :expired, layout: 'application'
    end

    @program = Program.find_by(slug: @auth_request.program)

    unless @program&.active?
      return render :error, locals: { message: 'Program not found or inactive' }, layout: 'application'
    end

    session['omniauth_scope'] = @program.oauth_scopes
    session['omniauth_context'] = {
      'flow' => 'popup',
      'auth_id' => @auth_request.auth_id,
      'program' => @program.slug
    }

    nextauth_url = ENV['NEXTAUTH_URL'].presence || request.base_url
    @oauth_url = "#{nextauth_url.to_s.chomp('/')}/auth/hack_club"
  end
end
