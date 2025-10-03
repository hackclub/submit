Rails.application.routes.draw do
  root 'home#index'
  # L4/L7 health check (no DB)
  get '/healthz', to: 'health#show'

  # OAuth entrypoint: builds the Identity Vault authorize URL
  get '/api/identity/url', to: 'identity#url'
  get '/identity/start', to: 'identity#start'

  # OAuth callback handler
  get '/identity', to: 'identity#callback'
  get '/admin/login', to: 'admin/sessions#new', as: :admin_login
  delete '/admin/logout', to: 'admin/sessions#destroy', as: :admin_logout
  get '/admin/callback', to: 'admin/sessions#callback', as: :admin_callback

  # Verify endpoint (API namespace)
  get '/api/verify', to: 'api/verify#index'
  
  # Authorize API endpoints
  post '/api/authorize', to: 'api/authorize#create'
  get '/api/authorize/:auth_id/status', to: 'api/authorize#status'
  
  # Popup authorization flow
  # Place callback before dynamic segment so "/callback" doesn't match :auth_id
  get '/popup/authorize/callback', to: 'popup/authorize#callback'
  get '/popup/authorize/:auth_id', to: 'popup/authorize#show', constraints: { auth_id: /[0-9a-f\-]{36}/ }

  # Admin
  namespace :admin do
    get '/', to: 'dashboard#index', as: :root
    resources :verification_attempts, only: [:index]
    resources :programs do
      member do
        post :activate
        post :deactivate
        post :activate_from_dash
        post :deactivate_from_dash
        post :regenerate_api_key
      end
    end
  resources :users, only: [:index, :create, :update, :destroy]

  # Catch-all for unknown admin routes -> custom 404
  match '*unmatched', to: 'errors#not_found', via: :all
  end

  # Mount ActionCable for hotwire-livereload and real-time features
  mount ActionCable.server => '/cable'

  # Program landing: /:program (only match HTML, avoid static asset requests)
  get '/:program', to: 'programs#show', as: :program, constraints: lambda { |req| !req.format || req.format.html? }
end
