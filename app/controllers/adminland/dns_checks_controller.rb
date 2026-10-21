class Adminland::DnsChecksController < AdminlandController
  def show
    @dns_check = Relay::DnsCheck.instance
  end

  def create
    Relay::DnsCheck.instance.check_dns_later
    redirect_to adminland_dns_check_path, notice: "Checking DNS. Give it a moment, then refresh"
  end
end
