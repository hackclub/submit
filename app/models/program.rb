
# == Schema Information
#
# Table name: programs
#
#  id                   :bigint           not null, primary key
#  accent               :string
#  active               :boolean          default(TRUE), not null
#  api_key              :string
#  background_primary   :string
#  background_secondary :string
#  description          :text
#  foreground_primary   :string
#  foreground_secondary :string
#  form_url             :string           not null
#  mappings             :jsonb            not null
#  name                 :string           not null
#  owner_email          :string
#  scopes               :jsonb            not null
#  slug                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_programs_on_api_key      (api_key) UNIQUE
#  index_programs_on_owner_email  (owner_email)
#  index_programs_on_slug         (slug) UNIQUE
#
class Program < ApplicationRecord
  before_save :downcase_color_fields
  before_validation :generate_api_key, on: :create

  def downcase_color_fields
    %i[background_primary background_secondary foreground_primary foreground_secondary accent].each do |field|
      val = self.send(field)
      self.send("#{field}=", val.downcase) if val.respond_to?(:downcase)
    end
  end

  after_initialize :set_default_colors

  def set_default_colors
    self.background_primary ||= '262626'
    self.background_secondary ||= '171717'
    self.foreground_primary ||= 'f5f5f5'
    self.foreground_secondary ||= 'a1a1a1'
    self.accent ||= 'ec3750'
  end

  HEX_REGEX = /\b(?:[A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\b/

  validates :background_primary, :background_secondary, :foreground_primary, :foreground_secondary, :accent,
            allow_blank: true,
            format: { with: HEX_REGEX, message: 'must be a valid hex color (without #)' }

  def is_bg_primary_dark?
    hex = background_primary
    return nil unless hex =~ HEX_REGEX && hex.length == 6
    r = hex[0..1].to_i(16)
    g = hex[2..3].to_i(16)
    b = hex[4..5].to_i(16)
    luminance = 0.299 * r + 0.587 * g + 0.114 * b
    luminance < 128
  end

  def is_bg_secondary_dark?
    hex = background_secondary
    return nil unless hex =~ HEX_REGEX && hex.length == 6
    r = hex[0..1].to_i(16)
    g = hex[2..3].to_i(16)
    b = hex[4..5].to_i(16)
    luminance = 0.299 * r + 0.587 * g + 0.114 * b
    luminance < 128
  end

  validates :slug, presence: true, uniqueness: true
  validates :form_url, presence: true
  validates :owner_email, presence: true
  validates :slug, format: { with: /\A[a-z0-9_-]+\z/, message: 'allows lowercase letters, numbers, dashes, and underscores only' }
  validates :api_key, presence: true, uniqueness: true
  validate  :validate_form_url
  validate  :validate_scopes
  validate  :validate_mappings
  validate  :validate_at_least_one_scope

  # scopes is a JSONB field storing booleans like:
  # {
  #   "first_name": true,
  #   "last_name": true,
  #   "full_name": false,
  #   "email": true,
  #   "birthday": false,
  #   "phone_number": false,
  #   "addresses": false
  # }

  def allowed_identity_fields
    default_always = %w[id verification_status ysws_eligible]
    return default_always if scopes.blank?

    permitted = default_always.dup
    scopes.each do |key, val|
      permitted << key.to_s if ActiveModel::Type::Boolean.new.cast(val)
    end
    permitted
  end

  ALLOWED_SCOPE_KEYS = %w[first_name last_name full_name email birthday phone_number addresses]

  def regenerate_api_key!
    self.api_key = generate_secure_api_key
    save!
  end

  private

  def generate_api_key
    self.api_key ||= generate_secure_api_key
  end

  def generate_secure_api_key
    loop do
      key = "pk_#{SecureRandom.hex(32)}"
      break key unless Program.exists?(api_key: key)
    end
  end

  def validate_form_url
    begin
      uri = URI.parse(form_url)
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        errors.add(:form_url, 'must be a valid http(s) URL')
      end
      allowed = ENV['FORM_URL_ALLOWED_HOSTS'].to_s.split(',').map(&:strip).reject(&:blank?)
      if allowed.any? && !allowed.include?(uri.host)
        errors.add(:form_url, "host '#{uri.host}' is not allowed")
      end
    rescue URI::InvalidURIError
      errors.add(:form_url, 'is invalid')
    end
  end

  def validate_scopes
    return if scopes.blank?
    unless scopes.is_a?(Hash)
      errors.add(:scopes, 'must be a JSON object')
      return
    end
    flat_keys = flatten_scope_keys(scopes).uniq
    unknown = flat_keys - ALLOWED_SCOPE_KEYS
    errors.add(:scopes, "contains unsupported keys: #{unknown.join(', ')}") if unknown.any?
  end

  def validate_at_least_one_scope
    # Require at least one scope enabled (true) among allowed scope keys
    if scopes.blank? || scopes.values.none? { |v| ActiveModel::Type::Boolean.new.cast(v) }
      errors.add(:scopes, 'must have at least one enabled scope')
    end
  end

  def flatten_scope_keys(h, acc = [])
    h.each do |k,v|
      if v.is_a?(Hash)
        flatten_scope_keys(v, acc)
      else
        acc << k.to_s
      end
    end
    acc
  end

  def validate_mappings
    return if mappings.blank?
    unless mappings.is_a?(Hash)
      errors.add(:mappings, 'must be a JSON object')
      return
    end
    mappings.each do |k, v|
      errors.add(:mappings, 'keys must be strings/symbols') unless k.is_a?(String) || k.is_a?(Symbol)
      errors.add(:mappings, 'values must be strings') unless v.is_a?(String)
    end
  end
end
