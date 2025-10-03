# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_08_27_020000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "admin_users", force: :cascade do |t|
    t.string "email", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
  end

  create_table "authorization_requests", force: :cascade do |t|
    t.string "auth_id", null: false
    t.string "program", null: false
    t.string "status", default: "pending", null: false
    t.string "popup_url"
    t.datetime "completed_at"
    t.string "idv_rec"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "identity_response"
    t.datetime "consumed_at"
    t.index ["auth_id"], name: "index_authorization_requests_on_auth_id", unique: true
    t.index ["consumed_at"], name: "index_authorization_requests_on_consumed_at"
    t.index ["created_at"], name: "index_authorization_requests_on_created_at"
    t.index ["program", "status"], name: "index_authorization_requests_on_program_and_status"
  end

  create_table "authorized_submit_tokens", force: :cascade do |t|
    t.string "submit_id", null: false
    t.string "idv_rec", null: false
    t.string "program"
    t.datetime "issued_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idv_rec"], name: "index_authorized_submit_tokens_on_idv_rec"
    t.index ["program"], name: "index_authorized_submit_tokens_on_program"
    t.index ["submit_id"], name: "index_authorized_submit_tokens_on_submit_id", unique: true
  end

  create_table "programs", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "form_url", null: false
    t.text "description"
    t.jsonb "scopes", default: {}, null: false
    t.jsonb "mappings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "owner_email"
    t.boolean "active", default: true, null: false
    t.string "background_primary"
    t.string "background_secondary"
    t.string "foreground_primary"
    t.string "accent"
    t.string "foreground_secondary"
    t.string "api_key"
    t.index ["api_key"], name: "index_programs_on_api_key", unique: true
    t.index ["owner_email"], name: "index_programs_on_owner_email"
    t.index ["slug"], name: "index_programs_on_slug", unique: true
  end

  create_table "user_journey_events", force: :cascade do |t|
    t.string "event_type", null: false
    t.string "program"
    t.string "idv_rec"
    t.string "email"
    t.string "request_ip"
    t.jsonb "metadata"
    t.bigint "verification_attempt_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_user_journey_events_on_created_at"
    t.index ["email"], name: "index_user_journey_events_on_email"
    t.index ["event_type"], name: "index_user_journey_events_on_event_type"
    t.index ["idv_rec"], name: "index_user_journey_events_on_idv_rec"
    t.index ["program"], name: "index_user_journey_events_on_program"
    t.index ["verification_attempt_id"], name: "index_user_journey_events_on_verification_attempt_id"
  end

  create_table "verification_attempts", force: :cascade do |t|
    t.string "idv_rec"
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.boolean "ysws_eligible"
    t.string "verification_status"
    t.string "rejection_reason"
    t.boolean "verified", default: false, null: false
    t.jsonb "identity_response"
    t.string "ip"
    t.string "program"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "submit_id"
    t.index ["created_at"], name: "index_verification_attempts_on_created_at"
    t.index ["email"], name: "index_verification_attempts_on_email"
    t.index ["idv_rec"], name: "index_verification_attempts_on_idv_rec"
    t.index ["program"], name: "index_verification_attempts_on_program"
    t.index ["submit_id"], name: "index_verification_attempts_on_submit_id_unique", unique: true, where: "(submit_id IS NOT NULL)"
    t.index ["verified"], name: "index_verification_attempts_on_verified"
  end

  add_foreign_key "user_journey_events", "verification_attempts"
end
