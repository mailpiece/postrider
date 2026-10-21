Autotuner.enabled = true

# Log suggestions for Loki / structured analysis.
Autotuner.reporter = proc do |heuristic_report|
  report = heuristic_report.to_s

  Rails.logger.info "GCAUTOTUNE: #{report}"

  RailsStructuredLogging.instrument_script "autotuner" do
    Rails.logger.info report.to_s
  end if defined? RailsStructuredLogging
end
