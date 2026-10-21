class User::Settings < ApplicationRecord
  belongs_to :account, default: -> { user.account }
  belongs_to :user

  def timezone
    if timezone_name.present?
      ActiveSupport::TimeZone[timezone_name] || default_timezone
    else
      default_timezone
    end
  end

  private
    def default_timezone
      ActiveSupport::TimeZone["UTC"]
    end
end
