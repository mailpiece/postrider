require "test_helper"

class Relay::SupervisorTest < ActiveSupport::TestCase
  class FakeLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def log(message)
      @messages << message
    end
  end

  setup do
    @logger = FakeLogger.new
    @supervisor = Relay::Supervisor.new(logger: @logger, poll_interval: 3600)
    Relay::Certificate.stubs(:renew_if_due)
    stub_tls_pem "cert-pem"
    AcmeDnsListener.stubs(:new).returns(fake_listener)
  end

  teardown do
    @supervisor.stop
  end

  test "starts every listener on start" do
    mx = fake_listener
    submission = fake_listener
    acme_dns = fake_listener
    mx.expects(:start).once
    submission.expects(:start).once
    acme_dns.expects(:start).once
    MxListener.stubs(:new).returns(mx)
    SubmissionListener.stubs(:new).returns(submission)
    AcmeDnsListener.stubs(:new).returns(acme_dns)

    @supervisor.start

    assert_includes @logger.messages, "[postrider] MxListener listening on 0.0.0.0:2525"
    assert_includes @logger.messages, "[postrider] SubmissionListener listening on 0.0.0.0:2525"
    assert_includes @logger.messages, "[postrider] AcmeDnsListener listening on 0.0.0.0:2525"
  end

  test "kicks ACME issuance on start" do
    stub_listeners fake_listener, fake_listener
    Relay::Certificate.expects(:renew_if_due).once

    @supervisor.start
  end

  test "retries a listener that could not boot and starts it once a certificate appears" do
    mx = fake_listener
    submission = fake_listener
    MxListener.stubs(:new).returns(mx)
    SubmissionListener.stubs(:new).raises(Relay::Certificate::Missing).then.returns(submission)
    stub_tls_pem nil

    @supervisor.start

    stub_tls_pem "cert-pem"
    mx.expects(:reload_tls).once
    submission.expects(:start).once

    # tick, not reconcile_tls_certificate: only tick starts listeners held for want of a cert.
    @supervisor.send(:tick)
  end

  test "reloads TLS on the running listeners when the certificate changes" do
    mx, submission = stub_listeners(fake_listener, fake_listener)
    stub_tls_pem "old-cert"

    @supervisor.start

    stub_tls_pem "new-cert"
    mx.expects(:reload_tls).once
    submission.expects(:reload_tls).once

    @supervisor.send(:reconcile_tls_certificate)
  end

  test "does not touch the listeners when the certificate is unchanged" do
    mx, submission = stub_listeners(fake_listener, fake_listener)

    @supervisor.start
    mx.expects(:reload_tls).never
    submission.expects(:reload_tls).never

    @supervisor.send(:reconcile_tls_certificate)
  end

  test "restarts a listener that stopped on its own" do
    stopped = fake_listener
    stopped.stubs(:stopped?).returns(true)
    restarted = fake_listener
    MxListener.stubs(:new).returns(stopped).then.returns(restarted)
    SubmissionListener.stubs(:new).returns(fake_listener)

    @supervisor.start
    restarted.expects(:start).once

    @supervisor.send(:tick)

    assert @logger.messages.any? { |message| message.include?("MxListener stopped unexpectedly") }
  end

  test "keeps trying to restart a listener whose restart fails" do
    stopped = fake_listener
    stopped.stubs(:stopped?).returns(true)
    MxListener.stubs(:new).returns(stopped).then.raises(RuntimeError, "address already in use")
    SubmissionListener.stubs(:new).returns(fake_listener)

    @supervisor.start
    2.times { @supervisor.send(:tick) }

    assert_equal 2, @logger.messages.count { |message| message.include?("MxListener failed to start") }
  end

  test "leaves a running listener alone" do
    stub_listeners fake_listener, fake_listener

    @supervisor.start
    @supervisor.send(:tick)

    assert_not @logger.messages.any? { |message| message.include?("stopped unexpectedly") }
  end

  test "stops every listener and halts the watcher on stop" do
    mx = fake_listener
    submission = fake_listener
    stub_listeners mx, submission
    mx.expects(:stop).once
    submission.expects(:stop).once

    @supervisor.start
    watcher = @supervisor.instance_variable_get(:@tls_watcher)
    @supervisor.stop

    assert_not watcher.join(1).alive?
    assert_nil @supervisor.instance_variable_get(:@tls_watcher)
  end

  test "keeps the watcher alive when a certificate check raises" do
    stub_listeners fake_listener, fake_listener
    supervisor = Relay::Supervisor.new(logger: @logger, poll_interval: 0.01)
    supervisor.stubs(:reconcile_tls_certificate).raises(RuntimeError, "boom")

    supervisor.start
    watcher = supervisor.instance_variable_get(:@tls_watcher)
    sleep 0.1

    assert watcher.alive?
    assert @logger.messages.any? { |message| message.include?("ERROR: Listener check failed") }
  ensure
    supervisor.stop
  end

  test "contains an exception while starting one listener and keeps the others" do
    submission = fake_listener
    MxListener.stubs(:new).raises(RuntimeError, "boom")
    SubmissionListener.stubs(:new).returns(submission)
    submission.expects(:start).once

    @supervisor.start

    assert @logger.messages.any? { |message| message.include?("ERROR: MxListener failed to start") }
  end

  test "reports a boot failure when a listener fails with a certificate already present" do
    MxListener.stubs(:new).raises(RuntimeError, "address already in use")
    SubmissionListener.stubs(:new).returns(fake_listener)

    @supervisor.start

    assert @supervisor.boot_failed?
  end

  test "does not report a boot failure while a listener is only waiting for a certificate" do
    MxListener.stubs(:new).raises(Relay::Certificate::Missing)
    SubmissionListener.stubs(:new).raises(Relay::Certificate::Missing)

    @supervisor.start

    assert_not @supervisor.boot_failed?
  end

  test "contains an exception while stopping one listener and keeps the others" do
    mx = fake_listener
    submission = fake_listener
    stub_listeners mx, submission
    mx.stubs(:stop).raises(RuntimeError, "boom")
    submission.expects(:stop).once

    @supervisor.start
    @supervisor.stop

    assert @logger.messages.any? { |message| message.include?("ERROR:") }
  end

  private
    def fake_listener
      mock.tap do |listener|
        listener.stubs(:start)
        listener.stubs(:stop)
        listener.stubs(:reload_tls)
        listener.stubs(:addresses).returns([ "0.0.0.0:2525" ])
      listener.stubs(:stopped?).returns(false)
      end
    end

    def stub_listeners(mx, submission)
      MxListener.stubs(:new).returns(mx)
      SubmissionListener.stubs(:new).returns(submission)
      [ mx, submission ]
    end

    def stub_tls_pem(pem)
      Relay::Certificate.stubs(:instance).returns(stub(pem: pem))
    end
end
