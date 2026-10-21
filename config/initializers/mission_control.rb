Rails.application.config.before_initialize do
  MissionControl::Jobs.base_controller_class = "AdminlandController"
  MissionControl::Jobs.show_console_help = false
end
