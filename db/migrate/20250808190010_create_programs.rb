class CreatePrograms < ActiveRecord::Migration[7.1]
  def change
    create_table :programs do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :form_url, null: false
      t.text :description
      t.jsonb :scopes, null: false, default: {}
      t.jsonb :mappings, null: false, default: {}

      t.timestamps
    end
    add_index :programs, :slug, unique: true
  end
end
