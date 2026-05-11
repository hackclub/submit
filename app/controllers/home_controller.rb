class HomeController < ApplicationController
  def index
  end

  def openapi
    send_file Rails.root.join('docs', 'openapi.yaml'),
              type: 'application/yaml',
              disposition: 'inline'
  end
end
