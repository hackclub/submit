class CreateAuthorizedSubmitTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :authorized_submit_tokens do |t|
      t.string :submit_id, null: false
      t.string :idv_rec, null: false
      t.string :program
      t.datetime :issued_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps
    end

    add_index :authorized_submit_tokens, :submit_id, unique: true
    add_index :authorized_submit_tokens, :idv_rec
    add_index :authorized_submit_tokens, :program
  end
end
