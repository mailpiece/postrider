module SupportHelper
  def support_email_address
    Rails.configuration.x.support.email_address
  end
end
