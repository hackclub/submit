class Admin::UsersController < Admin::BaseController
  before_action :require_superadmin!

  def index
    @users = AdminUser.order(:email)
    @new_user = AdminUser.new
  end

  def create
    @user = AdminUser.new(user_params)
    if @user.save
      flash[:success] = 'Admin user added.'
      redirect_to admin_users_path
    else
      @users = AdminUser.order(:email)
      @new_user = @user
      render :index, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @users = AdminUser.order(:email)
    @new_user = @user
    @new_user.errors.add(:email, 'has already been taken')
    render :index, status: :unprocessable_entity
  end

  def update
    @user = AdminUser.find(params[:id])
    if @user.update(user_params)
      flash[:success] = 'Admin user updated.'
      redirect_to admin_users_path
    else
      @users = AdminUser.order(:email)
      @new_user = AdminUser.new
      render :index, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @users = AdminUser.order(:email)
    @new_user = AdminUser.new
    @user.errors.add(:email, 'has already been taken')
    render :index, status: :unprocessable_entity
  end

  def destroy
    @user = AdminUser.find(params[:id])
    if @user == current_admin
      redirect_to admin_users_path, alert: 'Cannot delete yourself.'
    else
      @user.destroy
      flash[:success] = 'Admin user removed.'
      redirect_to admin_users_path
    end
  end

  private

  def user_params
    params.require(:admin_user).permit(:email, :role)
  end

  def require_superadmin!
    redirect_to admin_root_path, alert: 'Superadmin required' unless superadmin?
  end
end
