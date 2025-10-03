class ProgramsConfig
  # DEPRECATED: Configuration has moved to Program model (database backed).
  # Kept temporarily for compatibility; reads from Program when possible.

  def self.all
    # Return a hash-like structure to keep existing views functional
    Program.order(:name).each_with_object({}) do |p, h|
      h[p.slug] = { name: p.name, description: p.description, form_url: p.form_url, mappings: p.mappings }
    end
  end

  def self.find(id)
    p = Program.find_by(slug: id)
    return nil unless p
    { name: p.name, description: p.description, form_url: p.form_url, mappings: p.mappings, slug: p.slug }
  end
end
