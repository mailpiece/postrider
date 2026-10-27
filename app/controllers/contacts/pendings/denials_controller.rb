class Contacts::Pendings::DenialsController < ApplicationController
  def create
    Current.user.accessible_contacts.pending.deny_all

    respond_to do |format|
      format.html { redirect_to contacts_pending_path, notice: "Everyone who was waiting is now screened out" }
      format.json { head :no_content }
    end
  end
end
