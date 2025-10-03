# Ensure default superadmin exists
AdminUser.find_or_create_by!(email: 'leow@hackclub.com') do |u|
  u.role = :superadmin
end
