class AddIdentityResponseToAuthorizationRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :authorization_requests, :identity_response, :jsonb
  end
end
