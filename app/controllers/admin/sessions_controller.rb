class Admin::SessionsController < ApplicationController
  require 'base64'
  require 'net/http'
  require Rails.root.join('app/services/state_token')

  def new
    # Kick off OAuth to Identity Vault
    # Sign and bind state to session to prevent CSRF/state tampering
    session[:admin_state_nonce] = SecureRandom.hex(16)
    state = StateToken.generate({ purpose: 'admin_login' }, nonce: session[:admin_state_nonce])
    nextauth_url = ENV['NEXTAUTH_URL'].presence || request.base_url
    query = {
      client_id: ENV['IDENTITY_CLIENT_ID'],
      redirect_uri: File.join(nextauth_url, 'admin/callback'),
      response_type: 'code',
      scope: 'basic_info',
      state: state
    }
    auth_url = URI(ENV['IDENTITY_URL'].to_s + '/oauth/authorize')
    auth_url.query = URI.encode_www_form(query)
    redirect_to auth_url.to_s, allow_other_host: true
  end

  def callback
    code = params[:code]
    state = params[:state]
    return redirect_to root_path, alert: 'Missing code' unless code.present?

    token_uri = URI(ENV['IDENTITY_URL'].to_s + '/oauth/token')
    body = {
      code: code,
      client_id: ENV['IDENTITY_CLIENT_ID'],
      client_secret: ENV['IDENTITY_CLIENT_SECRET'],
      redirect_uri: File.join(ENV['NEXTAUTH_URL'].presence || request.base_url, 'admin/callback'),
      grant_type: 'authorization_code'
    }

    http = Net::HTTP.new(token_uri.host, token_uri.port)
      http.use_ssl = token_uri.scheme == 'https'
      http.open_timeout = 3
      http.read_timeout = 5
    req = Net::HTTP::Post.new(token_uri, { 'Content-Type' => 'application/json' })
    req.body = body.to_json
      begin
        res = http.request(req)
      rescue => e
        Rails.logger.error("Admin OAuth token exchange error: #{e.class}: #{e.message}")
        return redirect_to root_path, alert: 'OAuth failed'
      end
    return redirect_to root_path, alert: 'OAuth failed' unless res.is_a?(Net::HTTPSuccess)

    token_data = JSON.parse(res.body)

    me_uri = URI(ENV['IDENTITY_URL'].to_s + '/api/v1/me')
    http = Net::HTTP.new(me_uri.host, me_uri.port)
      http.use_ssl = me_uri.scheme == 'https'
      http.open_timeout = 3
      http.read_timeout = 5
    req = Net::HTTP::Get.new(me_uri)
    req['Authorization'] = "Bearer #{token_data['access_token']}"
      begin
        me_res = http.request(req)
      rescue => e
        Rails.logger.error("Admin profile fetch error: #{e.class}: #{e.message}")
        return redirect_to root_path, alert: 'Profile fetch failed'
      end
    return redirect_to root_path, alert: 'Profile fetch failed' unless me_res.is_a?(Net::HTTPSuccess)

  user_data = JSON.parse(me_res.body)['identity']
  user_data = IdentityNormalizer.normalize(user_data)
      # Verify and consume state
      state_data = StateToken.verify(state)
      if session[:admin_state_nonce].blank? || state_data.nil? || state_data['nonce'] != session[:admin_state_nonce]
        return redirect_to root_path, alert: 'OAuth failed'
      end
      session.delete(:admin_state_nonce)
    # Gate on AdminUser presence
  email = user_data['email']
    user = AdminUser.find_by(email: email)
    if user
        reset_session
        session[:admin_email] = email
      if user.ysws_author?
        flash[:success] = 'Welcome back!'
        redirect_to admin_programs_path
      else
        flash[:success] = 'Welcome back!'
        redirect_to admin_root_path
      end
    else
      redirect_to root_path, alert: 'Unauthorized'
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: 'Logged out'
  end
end
