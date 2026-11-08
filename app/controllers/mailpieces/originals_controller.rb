class Mailpieces::OriginalsController < ApplicationController
  include ActiveStorage::Streaming

  before_action :set_mailpiece

  def show
    if @mailpiece.postable.raw_email.attached?
      send_original @mailpiece.postable.raw_email.blob
    else
      head :not_found
    end
  end

  private
    def set_mailpiece
      @mailpiece = Current.user.accessible_mailpieces.find(params[:mailpiece_id])
    end

    def send_original(blob)
      response.headers["X-Content-Type-Options"] = "nosniff"
      send_stream(filename: "#{blob.filename.base}.txt", disposition: "inline", type: "text/plain; charset=utf-8") do |stream|
        blob.download { |chunk| stream.write chunk }
      end
    end
end
