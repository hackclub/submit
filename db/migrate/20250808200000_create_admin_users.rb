class CreateAdminUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :admin_users do |t|
      t.string :email, null: false
      t.integer :role, null: false, default: 0 # 0=admin, 1=superadmin

      t.timestamps
    end

    add_index :admin_users, :email, unique: true
  end
end
