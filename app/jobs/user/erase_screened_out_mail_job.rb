class User::EraseScreenedOutMailJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(user)
    user.erase_screened_out_mail_now
  end
end
