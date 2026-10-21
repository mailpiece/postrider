require "puma/plugin"

Puma::Plugin.create do
  def start(launcher)
    @launcher = launcher

    launcher.events.after_booted { boot }
    launcher.events.after_stopped { @supervisor&.stop }
    launcher.events.before_restart { @supervisor&.stop }
  end

  private
    def boot
      require File.expand_path("../../../config/environment", __dir__)
      @supervisor = Relay::Supervisor.new(logger: @launcher.log_writer)
      @supervisor.start
    end
end
