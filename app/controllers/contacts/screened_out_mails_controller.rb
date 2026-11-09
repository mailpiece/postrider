class Contacts::ScreenedOutMailsController < ApplicationController
  before_action :ensure_admin

  def destroy
    Current.user.erase_screened_out_mail_later

    respond_to do |format|
      format.html { redirect_to contacts_denied_path, notice: "Erasing the mail from screened-out senders" }
      format.json { head :accepted }
    end
  end
end
