class UserJourneyFlow
  require 'base64'
  require 'securerandom'
  require 'uri'

  # Generate a unique Submit ID for a verification flow
  def self.generate_submit_id
    SecureRandom.uuid
  end

  # Build state payload placed into OAuth 'state'
  def self.build_state(program:, submit_id:, original_params: nil, auth_id: nil)
    state = { program: program, submit_id: submit_id }
    state[:auth_id] = auth_id if auth_id.present?
    if original_params.present?
      # Cap length to 1024 chars and keep only ASCII-safe content
      sanitized = original_params.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      sanitized = sanitized[0, 1024]
      state[:originalParams] = sanitized.presence
    end
    state
  end

  def self.encode_state(state_hash)
    Base64.strict_encode64(state_hash.to_json)
  end

  def self.decode_state(encoded)
    JSON.parse(Base64.decode64(encoded))
  rescue
    { 'program' => encoded }
  end

  # Determine identity param name based on target form host
  # Returns [is_airtable, param_name]
  def self.identity_param_for(form_url)
    is_airtable = form_url.host == 'airtable.com'
    [is_airtable, is_airtable ? 'prefill_idv_rec' : 'idv_rec']
  end

  # Build the final form URL including idv_rec:submit_id and mapped fields
  def self.build_form_url(program_config:, identity_key:, user_data:, state_data:)
    form_url = URI(program_config[:form_url])
    is_airtable, identity_param = identity_param_for(form_url)

    raw_scopes = program_config[:scopes]
    scope_hash = if raw_scopes.respond_to?(:to_h)
                   raw_scopes.to_h
                 elsif raw_scopes.is_a?(Hash)
                   raw_scopes
                 else
                   {}
                 end.transform_keys { |k| k.to_s }
    boolean_type = ActiveModel::Type::Boolean.new
    scoped_fields = %w[first_name last_name full_name email birthday phone_number addresses slack_id]
    scope_enabled = lambda do |field|
      field_name = field.to_s
      return true unless scoped_fields.include?(field_name)
      boolean_type.cast(scope_hash[field_name])
    end

    append_param = lambda do |key, value|
      return if value.blank?
      encoded = URI.encode_www_form([[key, value]])
      form_url.query = [form_url.query, encoded].compact.join('&')
    end

    # Preserve original params if present
    if state_data['originalParams'].present?
      URI.decode_www_form(state_data['originalParams']).each do |k, v|
        append_param.call(k, v)
      end
    end

    # Airtable tweaks
    if is_airtable
      form_url.query = [form_url.query, 'hide_idv_rec=true'].compact.join('&')
    end

    submit_id = state_data['submit_id']
    idv_rec_with_submit = submit_id.present? ? "#{identity_key}:#{submit_id}" : identity_key
    append_param.call(identity_param, idv_rec_with_submit)

    # Mappings
    mappings = program_config[:mappings]
    if mappings.present?
      mappings.each do |user_field, form_field|
        value = user_data[user_field.to_s]
        next unless value.present?
        next unless scope_enabled.call(user_field)
        key = is_airtable ? "prefill_#{form_field}" : form_field
        append_param.call(key, value)
      end
    else
      default_fields = {
        'full_name' => 'Full+Name',
        'first_name' => 'First+Name',
        'last_name' => 'Last+Name',
        'email' => 'Email',
        'birthday' => 'Birthday',
        'phone_number' => 'Phone+Number',
        'slack_id' => 'Slack+ID'
      }
      default_fields.each do |field, airtable_name|
        next unless scope_enabled.call(field)
        value = user_data[field]
        key = is_airtable ? "prefill_#{airtable_name}" : field
        append_param.call(key, value)
      end

      # Address: expand primary address into individual fields
      if scope_enabled.call('addresses')
        addrs = user_data['addresses']
        addr = addrs.is_a?(Array) ? addrs.first : nil
        if addr.is_a?(Hash)
          address_fields = {
            'address_line_1' => 'line_1',
            'address_line_2' => 'line_2',
            'address_city' => 'city',
            'address_state' => 'state',
            'address_zip' => 'postal_code',
            'address_country' => 'country'
          }
          address_fields.each do |param_name, addr_key|
            key = is_airtable ? "prefill_#{param_name}" : param_name
            append_param.call(key, addr[addr_key])
          end
        end
      end
    end

    final_url = form_url.to_s
    final_url = final_url.gsub('%2B', '+') if is_airtable
    final_url
  end
end
