class Relay::Certificate::RenewalJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  limits_concurrency key: "tls_certificate_renewal", duration: 15.minutes

  def perform
    Relay::Certificate.instance.renew
  end
end
