class Admin::DashboardController < Admin::BaseController
  def index
    # YSWS Authors are redirected to Programs and cannot access the dashboard
    if current_admin&.ysws_author?
      return redirect_to admin_programs_path, alert: 'Dashboard is not available for YSWS Authors.'
    end
  # Recent journey events for visibility even when no verification_attempts records exist
  @events_per_page = 20
  @events_page = params[:events_page].to_i
  @events_page = 1 if @events_page <= 0
  @events_total_count = UserJourneyEvent.count
  @events_total_pages = @events_total_count.zero? ? 0 : (@events_total_count.to_f / @events_per_page).ceil
  if @events_total_pages > 0 && @events_page > @events_total_pages
    @events_page = @events_total_pages
  end
  events_offset = (@events_page - 1) * @events_per_page
  events_offset = 0 if events_offset.negative?
  @events = UserJourneyEvent.order(created_at: :desc).offset(events_offset).limit(@events_per_page)

    # Program analytics (event-based)
    @program_stats = UserJourneyEvent
                       .where(event_type: ['oauth_passed', 'oauth_failed'])
                       .group(:program)
                       .select(
                         'program',
                         "COUNT(*) AS total",
                         "COUNT(*) FILTER (WHERE event_type = 'oauth_passed') AS verified_count",
                         "COUNT(*) FILTER (WHERE event_type = 'oauth_failed') AS unverified_count"
                       )
                       .order('total DESC NULLS LAST')

  # Totals (event-based)
  @total_verified = UserJourneyEvent.where(event_type: 'oauth_passed').count
  @total_unverified = UserJourneyEvent.where(event_type: 'oauth_failed').count
  @total_attempts = @total_verified + @total_unverified
  end
end
