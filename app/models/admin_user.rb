# == Schema Information
#
# Table name: admin_users
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  role       :integer          default("admin"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_admin_users_on_email  (email) UNIQUE
#
class AdminUser < ApplicationRecord
  enum role: { admin: 0, superadmin: 1, ysws_author: 2 }

  # Normalize email to avoid case/whitespace duplicates leaking past DB/index
  before_validation do
    self.email = email.to_s.strip.downcase if email.present?
  end

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  validates :role, presence: true
end
