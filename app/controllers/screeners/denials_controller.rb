class Screeners::DenialsController < ApplicationController
  def create
    Current.user.accessible_contacts.pending.deny_all

    respond_to do |format|
      format.html { redirect_to screener_path, notice: "Everyone who was waiting is now screened out" }
      format.json { head :no_content }
    end
  end
end
