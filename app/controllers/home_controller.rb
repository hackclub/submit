class HomeController < ApplicationController
  def index
  end

  def openapi
    response.set_header('Access-Control-Allow-Origin', '*')
    render plain: Rails.root.join('docs', 'openapi.yaml').read,
           content_type: 'application/yaml'
  end
end
