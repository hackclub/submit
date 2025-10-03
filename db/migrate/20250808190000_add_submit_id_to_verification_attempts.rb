class AddSubmitIdToVerificationAttempts < ActiveRecord::Migration[7.1]
  def change
    add_column :verification_attempts, :submit_id, :string
    add_index :verification_attempts, :submit_id
  end
end
