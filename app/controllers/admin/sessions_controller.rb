class Admin::SessionsController < ApplicationController
  def new
    session['omniauth_scope'] = 'openid email name'
    session['omniauth_context'] = { 'flow' => 'admin' }
    redirect_to '/auth/hack_club'
  end

  def destroy
    reset_session
    redirect_to root_path, notice: 'Logged out'
  end
end
