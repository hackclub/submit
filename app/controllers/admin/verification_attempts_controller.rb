class Admin::VerificationAttemptsController < Admin::BaseController
  def index
    # YSWS Authors cannot access verification sessions
    if current_admin&.ysws_author?
      return redirect_to admin_programs_path, alert: 'Verification Sessions are not available for YSWS Authors.'
    end
    @filters = {
      q: params[:q].to_s.strip.presence,
      program: params[:program].to_s.strip.presence,
      result: params[:result].to_s.strip.presence,
      date_from: params[:date_from].to_s.strip.presence,
      date_to: params[:date_to].to_s.strip.presence,
      email: params[:email].to_s.strip.presence,
      idv_rec: params[:idv_rec].to_s.strip.presence,
      submit_id: params[:submit_id].to_s.strip.presence
    }

    events_scope = UserJourneyEvent.order(created_at: :desc)
    # Date range filters
    if @filters[:date_from]
      from = Time.zone.parse(@filters[:date_from]).beginning_of_day rescue nil
      events_scope = events_scope.where('created_at >= ?', from) if from
    end
    if @filters[:date_to]
      to = Time.zone.parse(@filters[:date_to]).end_of_day rescue nil
      events_scope = events_scope.where('created_at <= ?', to) if to
    end

    # Simple attribute filters
    events_scope = events_scope.where(program: @filters[:program]) if @filters[:program]
    events_scope = events_scope.where(email: @filters[:email]) if @filters[:email]
    events_scope = events_scope.where(idv_rec: @filters[:idv_rec]) if @filters[:idv_rec]
    events_scope = events_scope.where("metadata ->> 'submit_id' = ?", @filters[:submit_id]) if @filters[:submit_id]

    # Free text search: email / idv_rec / program / IP / slack_id (ILIKE) or exact submit_id
    if @filters[:q]
      q = @filters[:q]
      events_scope = events_scope.where(
        "email ILIKE :q OR idv_rec ILIKE :q OR program ILIKE :q OR request_ip ILIKE :q OR metadata ->> 'submit_id' = :q_eq OR metadata ->> 'slack_id' ILIKE :q",
        q: "%#{q}%", q_eq: q
      )
    end

    # Limit to a reasonable window
    events = events_scope.limit(1000)
    sessions = sessionize_events(events)

    # Session-level result filter (passed/failed/pending)
    if @filters[:result].present?
      case @filters[:result]
      when 'passed'
        sessions = sessions.select { |s| s[:result] == 'passed' }
      when 'failed'
        sessions = sessions.select { |s| s[:result].to_s.start_with?('failed') }
      when 'pending'
        sessions = sessions.select { |s| s[:result] == 'pending' }
      end
    end

    # Extra free text search at the session level (covers submit_id, slack_id etc.)
    if @filters[:q]
      qd = @filters[:q].downcase
      sessions = sessions.select do |s|
        [s[:program], s[:email], s[:idv_rec], s[:ip], s[:submit_id], s[:slack_id]].compact.any? { |v| v.to_s.downcase.include?(qd) }
      end
    end

    # Pagination (10 per page)
    @per_page = 10
    @page = params[:page].to_i
    @page = 1 if @page <= 0
    @total_count = sessions.length
    @total_pages = @total_count.zero? ? 0 : (@total_count.to_f / @per_page).ceil
    if @total_pages > 0 && @page > @total_pages
      @page = @total_pages
    end
    offset = (@page - 1) * @per_page
    offset = 0 if offset.negative?
    @session_groups = sessions.slice(offset, @per_page) || []
    @program_options = UserJourneyEvent.where.not(program: nil).distinct.order(:program).pluck(:program)
  end

  private

  # Group events into sessions by program and proximity, preferring matches on email or idv_rec; fallback to IP.
  def sessionize_events(events)
    evs = events.to_a.sort_by(&:created_at) # oldest first
    sessions = []
    session_by_submit = {}
    window = 30.minutes

    evs.each do |e|
      submit_id_ev = (e.metadata.is_a?(Hash) && (e.metadata['submit_id'] || e.metadata[:submit_id])) || nil

      # 1) Hard match by submit_id if present (no time window restriction)
      found = if submit_id_ev.present? && session_by_submit[submit_id_ev]
        session_by_submit[submit_id_ev]
      else
        # 2) Otherwise, find a recent compatible session by program + proximity + identifiers
        sessions.reverse.find do |s|
          same_program = (s[:program].present? && e.program.present?) ? (s[:program] == e.program) : true
          within_window = (e.created_at - s[:last_at]) <= window
          same_program && within_window && (
            (e.email.present? && s[:email].present? && e.email == s[:email]) ||
            (e.idv_rec.present? && s[:idv_rec].present? && e.idv_rec == s[:idv_rec]) ||
            (e.email.blank? && s[:email].blank? && e.idv_rec.blank? && s[:idv_rec].blank? && e.request_ip == s[:ip])
          )
        end
      end

      if found
        found[:events] << e
        found[:last_at] = e.created_at
        found[:email] ||= e.email
        found[:idv_rec] ||= e.idv_rec
        merge_meta_into_session(found, e)
        # update index if submit_id now known
        if found[:submit_id].present?
          session_by_submit[found[:submit_id]] ||= found
        elsif submit_id_ev.present?
          found[:submit_id] = submit_id_ev
          session_by_submit[submit_id_ev] ||= found
        end
      else
        s = {
          program: e.program,
          ip: e.request_ip,
          first_at: e.created_at,
          last_at: e.created_at,
          email: e.email,
          idv_rec: e.idv_rec,
          events: [e],
          first_name: nil,
          last_name: nil,
          original_params: nil,
          final_url: nil,
          result: nil,
          submit_id: nil,
          slack_id: nil,
          latest_oauth_result: nil,
          latest_oauth_time: nil
        }
        merge_meta_into_session(s, e)
        # index session by submit_id if available
        if s[:submit_id].present?
          session_by_submit[s[:submit_id]] ||= s
        elsif submit_id_ev.present?
          s[:submit_id] = submit_id_ev
          session_by_submit[submit_id_ev] ||= s
        end
        sessions << s
      end
    end

    # Finalize session results with precedence
    sessions.each do |s|
      # Use the latest OAuth result if available
      if s[:latest_oauth_result] == 'passed'
        s[:result] = 'passed'
        next
      elsif s[:latest_oauth_result] == 'failed'
        # Determine the specific failure reason
        if s[:rejected]
          s[:result] = 'failed - rejected'
        elsif s[:ysws_ineligible]
          s[:result] = 'failed - over 18'
        elsif s[:pending_hint]
          s[:result] = 'pending'
        else
          s[:result] = 'failed'
        end
        next
      end

      # Fallback for sessions without OAuth results
      # Explicit rejects
      if s[:rejected]
        s[:result] = 'failed - rejected'
        next
      end

      # Hard fails (age/ineligible etc.)
      if s[:ysws_ineligible]
        s[:result] = 'failed - over 18'
        next
      end

      # Other known failures
      if s[:failed_other]
        s[:result] = 'failed'
        next
      end

      # Pending hints or in-flight stages w/o rejection => pending
      if s[:pending_hint] || s[:saw_stage]
        s[:result] = 'pending'
      end
    end

    sessions.sort_by { |s| s[:last_at] }.reverse
  end

  def merge_meta_into_session(s, e)
    m = e.metadata.is_a?(Hash) ? e.metadata : {}
    fn = m['first_name'] || m[:first_name]
    ln = m['last_name'] || m[:last_name]
    slack = m['slack_id'] || m[:slack_id]
    
    s[:first_name] ||= fn.presence
    s[:last_name] ||= ln.presence
    s[:original_params] ||= (m['original_params'] || m[:original_params] || (m['query_params'] || m[:query_params]))
    s[:final_url] ||= (m['final_url'] || m[:final_url])
    s[:submit_id] ||= (m['submit_id'] || m[:submit_id])
    s[:slack_id] ||= slack.presence
    # capture rejection reason whenever present
    rej = m['rejection_reason'] || m[:rejection_reason]
    s[:rejection_reason] = rej if rej.present?

    # initialize flags
    s[:saw_stage] ||= false
    s[:verified_true] ||= false
    s[:pending_hint] ||= false
    s[:rejected] ||= false
    s[:ysws_ineligible] ||= false
    s[:failed_other] ||= false

    # mark that this session is in-flight through these stages
    if %w[oauth_start oauth_callback oauth_passed redirect_to_form verification_attempt].include?(e.event_type)
      s[:saw_stage] = true
    end

    case e.event_type
    when 'oauth_passed'
      # Track this as the latest OAuth result
      verification_status = m['verification_status'] || m[:verification_status]
      if verification_status == 'verified'
        s[:latest_oauth_result] = 'passed'
        s[:latest_oauth_time] = e.created_at
        s[:verified_true] = true
      end
    when 'oauth_failed'
      # Track this as the latest OAuth result
      s[:latest_oauth_result] = 'failed'
      s[:latest_oauth_time] = e.created_at
      reason = m['reason'] || m[:reason]
      case reason
      when 'rejected'
        s[:rejected] = true
        s[:rejection_reason] ||= rej if rej.present?
      when 'pending_verification'
        s[:pending_hint] = true
      when 'over_18'
        s[:ysws_ineligible] = true
      else
        s[:failed_other] = true
      end
    when 'verification_attempt'
      verified = m['verified']
      status = m['status'] || m[:status]
      rejection_reason = m['rejection_reason'] || m[:rejection_reason]
      error = m['error'] || m[:error]

      s[:verified_true] ||= (verified == true)
      s[:rejected] ||= rejection_reason.present?
      s[:rejection_reason] ||= rejection_reason if rejection_reason.present?
      s[:pending_hint] ||= (status.to_s == 'pending')
      s[:ysws_ineligible] ||= (error.to_s == 'ysws_ineligible')
      # mark other failures if explicitly flagged and not pending
      s[:failed_other] ||= (error.present? && status.to_s != 'pending' && !s[:rejected] && !s[:ysws_ineligible])
    end
  end
end
