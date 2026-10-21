class MailpiecesController < ApplicationController
  before_action :ensure_admin, only: :destroy
  before_action :set_mailpiece, only: %i[ show destroy ]

  def index
    set_page_and_extract_portion_from Current.user.accessible_mailpieces.delivered.preloaded.ordered
    fresh_when etag: [ @page.records, Current.user.accessible_mailpieces ]
  end

  def show
    @postable = @mailpiece.postable
  end

  def destroy
    @mailpiece.postable.destroy!

    respond_to do |format|
      format.html { redirect_to root_path, notice: "Mailpiece deleted" }
      format.json { head :no_content }
    end
  end

  private
    def set_mailpiece
      @mailpiece = Current.user.accessible_mailpieces.find(params[:id])
    end
end
