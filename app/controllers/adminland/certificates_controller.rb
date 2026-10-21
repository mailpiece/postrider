class Adminland::CertificatesController < AdminlandController
  def show
    @certificate = Relay::Certificate.instance
    @dns_check = Relay::DnsCheck.instance
  end
end
