class AddOwnerAndActiveToPrograms < ActiveRecord::Migration[7.1]
  def change
    add_column :programs, :owner_email, :string
    add_column :programs, :active, :boolean, null: false, default: true
    add_index :programs, :owner_email
  end
end
