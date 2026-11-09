class MailpiecesController < ApplicationController
  before_action :ensure_admin, only: :destroy
  before_action :set_mailpiece, only: %i[ show destroy ]
  before_action :set_status, only: :index

  def index
    set_page_and_extract_portion_from Current.user.accessible_mailpieces.indexed_by(@status).preloaded.ordered
    @domain = Current.user.domains.unverified_first.first if !@page.used? && @status == "all"
    fresh_when etag: [ @page.records, Current.user.accessible_mailpieces, Current.user.domains ]
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

    def set_status
      @status = params[:status].presence_in(Mailpiece::STATUSES) || "all"
    end
end
