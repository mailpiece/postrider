class DnsCheckJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(subject)
    subject.check_dns
  end
end
