class HomeController < ApplicationController
  def index
  end

  def openapi
    send_data Rails.root.join('docs', 'openapi.yaml').read,
              type: 'application/yaml',
              disposition: 'inline',
              filename: 'openapi.yaml'
  end
end
