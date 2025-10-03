class AddUniqueIndexToVerificationAttemptsSubmitId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # Remove non-unique index if it exists
    if index_exists?(:verification_attempts, :submit_id)
      remove_index :verification_attempts, :submit_id
    end
    # Add a unique, partial index to enforce one-time use when submit_id is present
    add_index :verification_attempts, :submit_id, unique: true, algorithm: :concurrently, where: "submit_id IS NOT NULL", name: "index_verification_attempts_on_submit_id_unique"
  end

  def down
    if index_exists?(:verification_attempts, name: "index_verification_attempts_on_submit_id_unique")
      remove_index :verification_attempts, name: "index_verification_attempts_on_submit_id_unique"
    end
    add_index :verification_attempts, :submit_id unless index_exists?(:verification_attempts, :submit_id)
  end
end
