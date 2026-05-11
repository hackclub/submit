class HomeController < ApplicationController
  def index
  end

  def openapi
    render plain: Rails.root.join('docs', 'openapi.yaml').read,
           content_type: 'application/yaml'
  end
end
