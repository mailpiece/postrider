require "test_helper"

class ErrorReportingTest < ActiveSupport::TestCase
  class FakeSmtpd
    def log(*, **) = nil
  end

  class FakeListener < FakeSmtpd
    include ErrorReporting

    attr_writer :shutdown

    def initialize
      @shutdown = false
    end

    def shutdown?
      @shutdown
    end
  end

  setup do
    @listener = FakeListener.new
  end

  test "reports a genuine application error raised at ERROR severity" do
    report = assert_error_reported(RuntimeError) do
      @listener.log(nil, Logger::ERROR, "boom", err: RuntimeError.new("boom"))
    end

    assert_equal "boom", report.error.message
    assert_equal :error, report.severity
    assert_equal "smtp", report.source
    assert_not report.handled
  end

  test "reports a genuine application error raised at FATAL severity" do
    assert_error_reported(RuntimeError) do
      @listener.log(nil, Logger::FATAL, "boom", err: RuntimeError.new("boom"))
    end
  end

  test "does not report MailSmtp::Error subclasses, since the server already handles them" do
    assert_no_error_reported do
      @listener.log(nil, Logger::ERROR, "pipelining", err: MailSmtp::PipeliningNotSupported.new)
    end
  end

  test "does not report errors raised while the listener is shutting down" do
    @listener.shutdown = true

    assert_no_error_reported do
      @listener.log(nil, Logger::FATAL, "stream closed", err: IOError.new("stream closed in another thread"))
    end
  end

  test "does not report a client dropping its TLS connection without close_notify" do
    assert_no_error_reported do
      @listener.log(nil, Logger::FATAL, "eof", err: OpenSSL::SSL::SSLError.new("SSL_read: unexpected eof while reading"))
    end
  end

  test "does not report a client resetting or breaking the connection" do
    [ Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT, EOFError ].each do |error_class|
      assert_no_error_reported do
        @listener.log(nil, Logger::FATAL, "dropped", err: error_class.new)
      end
    end
  end

  test "does not report a failed TLS handshake, which reflects the client's capabilities" do
    [ "state=error: unsupported protocol", "state=error: no shared cipher" ].each do |reason|
      assert_no_error_reported do
        @listener.log(nil, Logger::ERROR, "handshake", err: OpenSSL::SSL::SSLError.new("SSL_accept returned=1 errno=0 #{reason}"))
      end
    end
  end
end
