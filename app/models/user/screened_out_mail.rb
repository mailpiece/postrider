module User::ScreenedOutMail
  extend ActiveSupport::Concern

  def screened_out_mail
    InboundEmail.held.where(contact: accessible_contacts.denied)
  end

  def erase_screened_out_mail_later
    User::EraseScreenedOutMailJob.perform_later(self)
  end

  # The events go first: they are found through the mail they are about.
  def erase_screened_out_mail_now
    Event.purge Event.where(eventable: screened_out_mail)
    InboundEmail.purge screened_out_mail
  end
end
