class Screeners::FlaggedDenialsController < ApplicationController
  def create
    Current.user.accessible_contacts.pending.deny_flagged

    respond_to do |format|
      format.html { redirect_to screener_path, notice: "Everyone the spam check flagged is now screened out" }
      format.json { head :no_content }
    end
  end
end
