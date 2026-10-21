class SuppressionsController < ApplicationController
  before_action :ensure_admin, only: :destroy

  def index
    set_page_and_extract_portion_from Current.user.accessible_suppressions.ordered
    fresh_when etag: @page.records
  end

  def destroy
    Current.user.accessible_suppressions.find(params[:id]).destroy!

    respond_to do |format|
      format.html { redirect_to suppressions_path, notice: "Suppression removed" }
      format.json { head :no_content }
    end
  end
end
