threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3010)

plugin :tmp_restart

plugin :solid_queue unless ENV["SOLID_QUEUE_IN_PUMA"] == "false"

plugin :postrider unless ENV["RAILS_ENV"] == "test" || ENV["RELAY_IN_PUMA"] == "false"

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
