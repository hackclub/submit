class CreateAuthorizationRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :authorization_requests do |t|
      t.string :auth_id, null: false
      t.string :program, null: false
      t.string :status, default: 'pending', null: false
      t.string :popup_url
      t.datetime :completed_at
      t.string :idv_rec

      t.timestamps
    end

    add_index :authorization_requests, :auth_id, unique: true
    add_index :authorization_requests, [:program, :status]
    add_index :authorization_requests, :created_at
  end
end
