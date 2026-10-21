class JsonEventSubscriber
  # Rails hands these over unfiltered: a delivered message whole, and a job's records, which to_json would dump.
  UNLOGGED_PAYLOAD_KEYS = %i[ mail arguments ]

  def initialize(io)
    @io = io
  end

  def emit(event)
    @io.write "#{line_for(event).to_json}\n"
  end

  private
    def line_for(event)
      event.except(:source_location).merge(payload: loggable(event[:payload]))
    end

    def loggable(payload)
      if payload.is_a?(Hash)
        payload.except(*UNLOGGED_PAYLOAD_KEYS)
      else
        payload
      end
    end
end
