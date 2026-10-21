class Relay::Supervisor
  LISTENER_CLASSES = [ MxListener, SubmissionListener, AcmeDnsListener ].freeze

  def initialize(logger:, poll_interval: 60)
    @logger = logger
    @poll_interval = poll_interval
    @listeners = {}
    @pending_listener_classes = []
    @failed_listener_classes = []
  end

  def start
    @pending_listener_classes = LISTENER_CLASSES.dup
    @failed_listener_classes = []
    start_pending_listeners
    watch_tls_certificate
    renew_tls_certificate_if_due
  end

  def boot_failed?
    @failed_listener_classes.any?
  end

  def stop
    stop_watching_tls_certificate
    @listeners.each_value { |listener| stop_listener(listener) }
    @listeners.clear
    @pending_listener_classes.clear
    @failed_listener_classes.clear
  end

  private
    def start_pending_listeners
      @pending_listener_classes.dup.each { |listener_class| start_listener(listener_class) }
    end

    def start_listener(listener_class)
      listener = listener_class.new
      listener.start
      @listeners[listener_class] = listener
      @pending_listener_classes.delete(listener_class)
      @failed_listener_classes.delete(listener_class)
      log "#{listener_class.name} listening on #{listener.addresses.join(", ")}"
    rescue Relay::Certificate::Missing
      log "#{listener_class.name} waiting for a TLS certificate before starting"
    rescue StandardError => error
      @failed_listener_classes |= [ listener_class ]
      log_error "#{listener_class.name} failed to start", error
    end

    # Queue rather than sleep: a wakeup during tick is otherwise lost and SIGTERM
    # can wait a full poll interval before listeners drain.
    def watch_tls_certificate
      @loaded_tls_state = tls_certificate_state
      @tls_watcher_stop = Queue.new
      @tls_watcher = Thread.new do
        loop do
          break if @tls_watcher_stop.pop(timeout: @poll_interval)
          tick
        rescue StandardError => error
          log_error "Listener check failed; will retry", error
        end
      end
    end

    # Reconcile before starting so a pending listener boots in the same tick the cert arrives.
    def tick
      requeue_stopped_listeners
      reconcile_tls_certificate
      start_pending_listeners
    end

    # Requeue onto pending so startup's boot path retries; drain first — in-flight
    # connections may outlive a dead acceptor.
    def requeue_stopped_listeners
      @listeners.select { |_listener_class, listener| listener.stopped? }.each do |listener_class, listener|
        log "#{listener_class.name} stopped unexpectedly; restarting it"
        stop_listener(listener)
        @listeners.delete(listener_class)
        @pending_listener_classes |= [ listener_class ]
      end
    end

    # Only mark loaded after a successful reload, or every tick rediscovers the same change.
    def reconcile_tls_certificate
      current = tls_certificate_state

      if current != @loaded_tls_state
        log "TLS certificate change detected"
        @loaded_tls_state = current if reload_listeners_tls
      end
    end

    def tls_certificate_state
      Relay::Certificate.instance.pem
    end

    def reload_listeners_tls
      @listeners.each_value(&:reload_tls)
      log "Reloaded TLS contexts on running listeners" if @listeners.any?
      true
    rescue StandardError => error
      log_error "TLS certificate reload failed; will retry", error
      false
    end

    def renew_tls_certificate_if_due
      Relay::Certificate.renew_if_due
    rescue StandardError => error
      log_error "Certificate renewal check failed", error
    end

    def stop_watching_tls_certificate
      if watcher = @tls_watcher
        @tls_watcher_stop << :stop
        watcher.join
        @tls_watcher = nil
      end
    end

    def stop_listener(listener)
      log "Stopping #{listener.class.name}..."
      listener.stop
    rescue StandardError => error
      log_error "#{listener.class.name} failed to stop", error
    end

    def log(message)
      @logger.log "[postrider] #{message}"
    end

    def log_error(message, error)
      log "ERROR: #{message}: #{error.class}: #{error.message}"
      Array(error.backtrace).first(10).each { |line| log "  #{line}" }
    end
end
