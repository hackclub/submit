class SeedProgramsFromConfig < ActiveRecord::Migration[7.1]
  def up
    say_with_time 'Seeding Programs from ProgramsConfig (if present)' do
      if Object.const_defined?(:ProgramsConfig)
        configs = ProgramsConfig.all
        configs.each do |slug, cfg|
          Program.find_or_create_by!(slug: slug) do |p|
            p.name = cfg[:name] || slug.titleize
            p.form_url = cfg[:form_url]
            p.description = cfg[:description]
            p.mappings = cfg[:mappings] || {}
            p.scopes = {}
          end
        end
      end
    end
  end

  def down
    # no-op; do not delete data
  end
end
