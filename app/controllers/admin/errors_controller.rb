class Admin::ErrorsController < Admin::BaseController
  skip_before_action :require_admin!

  def not_found
    respond_to do |format|
      format.html { render status: :not_found }
      format.json { render json: { error: 'Not Found' }, status: :not_found }
      format.all  { head :not_found }
    end
  end
end
