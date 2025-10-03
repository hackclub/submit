class AddConsumedAtToAuthorizationRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :authorization_requests, :consumed_at, :datetime
    add_index :authorization_requests, :consumed_at
  end
end
