class CreateVerificationAttempts < ActiveRecord::Migration[7.1]
  def change
    create_table :verification_attempts do |t|
      t.string :idv_rec
      t.string :first_name
      t.string :last_name
      t.string :email
      t.boolean :ysws_eligible
      t.string :verification_status
      t.string :rejection_reason
      t.boolean :verified, null: false, default: false
      t.jsonb :identity_response
      t.string :ip
      t.string :program
      t.timestamps
    end

    add_index :verification_attempts, :idv_rec
    add_index :verification_attempts, :email
    add_index :verification_attempts, :verified
    add_index :verification_attempts, :program
    add_index :verification_attempts, :created_at
  end
end
