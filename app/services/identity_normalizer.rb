class IdentityNormalizer
  # Normalize user_data from Identity service
  # - addresses: when multiple, keep only the primary one (by primary flag or tags includes 'primary')
  def self.normalize(user_data)
    return user_data unless user_data.is_a?(Hash)

    normalized = user_data.deep_dup
    # Ensure consistent 'email' key
    if normalized['email'].to_s.strip.empty? && normalized['primary_email'].present?
      normalized['email'] = normalized['primary_email']
    end
    addrs = normalized['addresses'] || normalized[:addresses]
    if addrs.is_a?(Array) && addrs.any?
      primary_list = addrs.select do |a|
        next false unless a.is_a?(Hash)
        a_primary = a['primary'] || a[:primary]
        tags = a['tags'] || a[:tags]
        has_primary_tag = false
        if tags.respond_to?(:include?)
          has_primary_tag ||= tags.include?('primary') || tags.include?(:primary)
        end
        a_primary == true || has_primary_tag
      end
      chosen = (primary_list.first || addrs.first)
      normalized['addresses'] = [chosen]
    end

    first = normalized['first_name'].to_s.strip
    last  = normalized['last_name'].to_s.strip
    if first.present? || last.present?
      normalized['full_name'] = [first, last].reject(&:blank?).join(' ').strip
    end

    normalized
  end
end
