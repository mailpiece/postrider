require "test_helper"

class Relay::Certificate::RenewalJobTest < ActiveJob::TestCase
  test "perform renews the singleton certificate" do
    certificate = Relay::Certificate.instance
    Relay::Certificate.stubs(:instance).returns(certificate)
    certificate.expects(:renew)

    Relay::Certificate::RenewalJob.perform_now
  end
end
