class CreateUserJourneyEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :user_journey_events do |t|
      t.string :event_type, null: false
      t.string :program
      t.string :idv_rec
      t.string :email
      t.string :request_ip
      t.jsonb :metadata
      t.references :verification_attempt, foreign_key: true
      t.timestamps
    end
    add_index :user_journey_events, :event_type
    add_index :user_journey_events, :program
    add_index :user_journey_events, :idv_rec
    add_index :user_journey_events, :email
    add_index :user_journey_events, :created_at
  end
end
