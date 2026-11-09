class Adminland::PausesController < AdminlandController
  before_action :set_pause, only: :destroy

  def index
    @pauses = Pause.ordered
  end

  def destroy
    @pause.resume

    redirect_to adminland_pauses_path, notice: "Resumed sending to #{@pause.provider_label}"
  end

  private
    def set_pause
      @pause = Pause.find(params[:id])
    end
end
