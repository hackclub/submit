class AddApiKeyToPrograms < ActiveRecord::Migration[7.1]
  def change
    add_column :programs, :api_key, :string
    add_index :programs, :api_key, unique: true
  end
end
