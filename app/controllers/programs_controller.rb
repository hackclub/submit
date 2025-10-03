class ProgramsController < ApplicationController
  layout 'program'

  def show
    @program = Program.find_by(slug: params[:program])
    if @program.nil?
      @requested_program = params[:program]
      # Render a styled not-found card instead of redirecting so user keeps context
      return render :not_found, status: :not_found
    end

  # Program page visit starts a new session flow: always generate a new submit_id
  # so each visit is treated as a fresh submission session.
  session[:submit_id] = SecureRandom.uuid

    # Log journey event for program page view
    UserJourneyEvent.create!(
      event_type: 'program_page',
      program: @program.slug,
      request_ip: request.remote_ip,
      metadata: { user_agent: request.user_agent, query_params: request.query_parameters, submit_id: session[:submit_id] }
    ) rescue nil
  end
end
