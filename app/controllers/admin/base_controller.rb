class Admin::BaseController < ApplicationController
  layout 'admin'
  before_action :require_admin!
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  helper_method :current_admin, :superadmin?

  private

  def require_admin!
    # Expect email set in session[:admin_email] after OAuth
    email = session[:admin_email]
    user = email.present? ? AdminUser.find_by(email: email) : nil
    unless user
      redirect_to admin_login_path, alert: 'Unauthorized'
    end
  end

  def current_admin
    return @current_admin if defined?(@current_admin)
    email = session[:admin_email]
    @current_admin = email.present? ? AdminUser.find_by(email: email) : nil
  end

  def superadmin?
    current_admin&.superadmin?
  end

  def render_not_found
    respond_to do |format|
      format.html { render 'admin/errors/not_found', status: :not_found }
      format.json { render json: { error: 'Not Found' }, status: :not_found }
      format.all  { head :not_found }
    end
  end
end
