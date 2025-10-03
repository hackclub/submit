class AddColorsToPrograms < ActiveRecord::Migration[7.1]
  def change
    add_column :programs, :background_primary, :string
    add_column :programs, :background_secondary, :string
    add_column :programs, :foreground_primary, :string
    add_column :programs, :accent, :string
  end
end
