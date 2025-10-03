class Admin::ProgramsController < Admin::BaseController
  before_action :set_program, only: [:edit, :update, :destroy, :activate, :deactivate, :activate_from_dash, :deactivate_from_dash, :regenerate_api_key]
  before_action :authorize_create!, only: [:new, :create]
  before_action :authorize_modify!, only: [:edit, :update]
  before_action :require_superadmin_for_destroy, only: [:destroy]

  def index
    if current_admin&.ysws_author?
      @programs = Program.where(owner_email: current_admin.email).order(:name)
    else
      @programs = Program.order(:name)
    end
  end

  def new
    @program = Program.new
  end

  def create
  attrs = program_params
  coerce_boolean_scopes!(attrs)
  parse_mappings_json!(attrs)
  restrict_sensitive_scopes_for_author!(attrs)
  # owner_email must always be present
  if current_admin&.ysws_author?
    attrs[:owner_email] = current_admin.email
  end
  @program = Program.new(attrs)
  @program.errors.add(:owner_email, 'is required') if @program.owner_email.blank?
  if @program.save
    # If the program is a YSWS program (by slug or other logic), invite owner as ysws_author
    if @program.slug.to_s.start_with?("ysws") && @program.owner_email.present?
      admin_user = AdminUser.find_by(email: @program.owner_email)
      if admin_user.nil?
        AdminUser.create(email: @program.owner_email, role: :ysws_author)
      end
    end
    flash[:success] = 'Program created.'
    redirect_to admin_programs_path
  else
    render :new, status: :unprocessable_entity
  end
  end

  def edit; end

  def update
    attrs = program_params
    coerce_boolean_scopes!(attrs)
    parse_mappings_json!(attrs)
    # ysws_author cannot change ownership
    attrs.delete(:owner_email) if current_admin&.ysws_author?
    restrict_sensitive_scopes_for_author!(attrs, existing: @program)
    # Prevent clearing owner_email
    attrs[:owner_email] = @program.owner_email if attrs[:owner_email].blank?
    if @program.update(attrs)
        flash[:success] = 'Program updated.'
        redirect_to admin_programs_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @program.destroy
    flash[:success] = 'Program deleted.'
    redirect_to admin_programs_path
  end

  private
  def set_program
    @program = Program.find(params[:id])
  end

  def program_params
    # Strong params: explicitly permit allowed scope keys; return a plain Ruby hash.
    raw = params.require(:program)
    permitted = raw.permit(:slug, :name, :form_url, :description, :mappings, :active, :owner_email,
      :background_primary, :background_secondary, :foreground_primary, :foreground_secondary, :accent,
      scopes: Program::ALLOWED_SCOPE_KEYS)
    # Normalize scopes to a plain hash (may be ActionController::Parameters)
    if permitted[:scopes].is_a?(ActionController::Parameters)
      permitted[:scopes] = permitted[:scopes].to_h
    end
    permitted.to_h
  end

  # Convert checkbox values to booleans
  def coerce_boolean_scopes!(attrs)
  scopes = attrs[:scopes].is_a?(Hash) ? attrs[:scopes] : {}
    attrs[:scopes] = deep_cast_booleans(scopes)
  end

  # Recursively cast any truthy/falsey form values down the scopes tree.
  def deep_cast_booleans(value)
    case value
    when Hash
      value.each_with_object({}) { |(k,v), h| h[k] = deep_cast_booleans(v) }
    when Array
      value.map { |v| deep_cast_booleans(v) }
    else
      ActiveModel::Type::Boolean.new.cast(value)
    end
  end

  # Accept mappings as JSON from textarea; keep as hash, add error on parse failure
  def parse_mappings_json!(attrs)
    raw = attrs[:mappings]
    return if raw.blank? || raw.is_a?(Hash)
    parsed = JSON.parse(raw) rescue nil
    if parsed.is_a?(Hash)
      attrs[:mappings] = parsed
    else
      @program ||= Program.new
      @program.errors.add(:mappings, 'must be valid JSON object')
    end
  end

  # Prevent ysws_author from enabling sensitive scopes (birthday, phone_number, addresses)
  def restrict_sensitive_scopes_for_author!(attrs, existing: nil)
    return unless current_admin&.ysws_author?
  scopes = attrs[:scopes].is_a?(Hash) ? attrs[:scopes] : {}
  return if scopes.empty?
    sensitive = %w[birthday phone_number addresses]
    sensitive.each do |k|
      next unless scopes.key?(k)
      proposed = ActiveModel::Type::Boolean.new.cast(scopes[k])
      if proposed
        # Allow enabling only if the existing record already had it on (i.e., unchanged true)
        prev_on = existing ? ActiveModel::Type::Boolean.new.cast(existing.scopes.to_h[k]) : false
        unless prev_on
          # Reject by forcing false and adding an error message for UX
          scopes[k] = false
          (@program || existing || Program.new).errors.add(:scopes, "#{k.humanize} can only be enabled by an admin")
        end
      end
    end
    attrs[:scopes] = scopes
  end

  def authorize_create!
    # superadmins, admins, and ysws_authors can access new/create
    unless current_admin&.superadmin? || current_admin&.admin? || current_admin&.ysws_author?
      redirect_to admin_root_path, alert: 'Unauthorized'
    end
  end

  def authorize_modify!
    return if current_admin&.superadmin? || current_admin&.admin?
    # ysws_author can edit/update only owned programs
    if current_admin&.ysws_author?
      return if @program&.owner_email.present? && @program.owner_email == current_admin.email
    end
    redirect_to admin_programs_path, alert: 'Unauthorized'
  end

  public
  def activate
    if current_admin&.superadmin? || current_admin&.admin? || (current_admin&.ysws_author? && @program.owner_email == current_admin.email)
      @program.update(active: true)
      flash[:success] = 'Program activated.'
      redirect_to admin_programs_path
    else
      redirect_to admin_programs_path, alert: 'Unauthorized'
    end
  end

  def activate_from_dash
    if current_admin&.superadmin? || current_admin&.admin? || (current_admin&.ysws_author? && @program.owner_email == current_admin.email)
      @program.update(active: true)
      flash[:success] = 'Program activated.'
      redirect_to current_admin.ysws_author? ? admin_programs_path : admin_root_path
    else
      redirect_to current_admin.ysws_author? ? admin_programs_path : admin_root_path, alert: 'Unauthorized'
    end
  end

  def deactivate
    if current_admin&.superadmin? || current_admin&.admin? || (current_admin&.ysws_author? && @program.owner_email == current_admin.email)
      @program.update(active: false)
      flash[:success] = 'Program deactivated.'
      redirect_to admin_programs_path
    else
      redirect_to admin_programs_path, alert: 'Unauthorized'
    end
  end

  def deactivate_from_dash
    if current_admin&.superadmin? || current_admin&.admin? || (current_admin&.ysws_author? && @program.owner_email == current_admin.email)
      @program.update(active: false)
      flash[:success] = 'Program deactivated.'
      redirect_to current_admin.ysws_author? ? admin_programs_path : admin_root_path
    else
      redirect_to current_admin.ysws_author? ? admin_programs_path : admin_root_path, alert: 'Unauthorized'
    end
  end

  def regenerate_api_key
    # Check authorization - similar to edit/update permissions
    return unless authorize_api_key_access!
    
    begin
      @program.regenerate_api_key!
      render json: { api_key: @program.api_key }, status: :ok
    rescue => e
      render json: { error: 'Failed to regenerate API key' }, status: :internal_server_error
    end
  end

  def require_superadmin_for_destroy
    unless superadmin?
      redirect_to admin_programs_path, alert: 'Only superadmins can delete programs.'
    end
  end

  private

  def authorize_api_key_access!
    return true if current_admin&.superadmin? || current_admin&.admin?
    # ysws_author can regenerate API key for owned programs
    if current_admin&.ysws_author?
      return true if @program&.owner_email.present? && @program.owner_email == current_admin.email
    end
    render json: { error: 'Unauthorized' }, status: :unauthorized
    false
  end
end
