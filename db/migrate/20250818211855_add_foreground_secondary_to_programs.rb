class AddForegroundSecondaryToPrograms < ActiveRecord::Migration[7.1]
  def change
    add_column :programs, :foreground_secondary, :string
  end
end
