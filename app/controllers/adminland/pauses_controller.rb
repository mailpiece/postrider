class Adminland::PausesController < AdminlandController
  def index
    @pauses = Pause.ordered
  end

  def destroy
    pause = Pause.find(params[:id])
    pause.resume

    redirect_to adminland_pauses_path, notice: "Resumed sending to #{pause.provider_label}"
  end
end
