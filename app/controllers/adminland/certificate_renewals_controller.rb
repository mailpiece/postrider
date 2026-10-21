class Adminland::CertificateRenewalsController < AdminlandController
  def create
    Relay::Certificate.instance.renew_later
    redirect_to adminland_certificate_path, notice: "Renewal started. Give it a minute, then refresh"
  end
end
