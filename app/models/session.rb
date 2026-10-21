class Session < ApplicationRecord
  SUDO_DURATION = 30.minutes

  belongs_to :identity

  def sudo
    touch(:sudo_at)
  end

  def sudo?
    sudo_at&.after?(SUDO_DURATION.ago)
  end
end
