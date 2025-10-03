class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  # Expose current_admin globally so non-admin controllers/views (e.g., Home) can detect admin sessions
  helper_method :current_admin

  private
  # Safely join URL parts without breaking the scheme (avoid File.join for URLs)
  def join_url(base, *parts)
    b = base.to_s.chomp('/')
    segs = parts.flatten.compact.map { |p| p.to_s.sub(%r{^/}, '') }
    ([b] + segs).join('/')
  end
  def current_admin
    return @current_admin if defined?(@current_admin)
    email = session[:admin_email]
    @current_admin = email.present? ? AdminUser.find_by(email: email) : nil
  end
end
