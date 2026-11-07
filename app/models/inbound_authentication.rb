class InboundAuthentication
  def self.verdicts(data, ip:, helo:, mail_from:)
    new(data, ip:, helo:, mail_from:).verdicts
  end

  def initialize(data, ip: nil, helo: nil, mail_from: nil)
    @data = data.gsub(/\r?\n/, "\r\n")
    @ip = ip
    @helo = helo
    @mail_from = mail_from
  end

  def verdicts
    MailAuth.new(@data, ip: @ip, helo: @helo, mail_from: @mail_from).verdicts
  end
end
