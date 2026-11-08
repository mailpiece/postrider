class Contacts::DeniedsController < ApplicationController
  before_action :ensure_admin, only: :destroy

  def show
    set_page_and_extract_portion_from Current.user.accessible_contacts.denied.ordered
    fresh_when etag: @page.records
  end

  def destroy
    Current.user.erase_screened_out_mail_later

    respond_to do |format|
      format.html { redirect_to contacts_denied_path, notice: "Erasing the mail from screened-out senders" }
      format.json { head :accepted }
    end
  end
end
