class InboundAuthentication
  class << self
    def verdicts(data, ip:, helo:, mail_from:)
      new(data, ip:, helo:, mail_from:).verdicts
    end

    def settled_verdicts(data, ip:, helo:, mail_from:, within:, slots: nil)
      new(data, ip:, helo:, mail_from:).settled_verdicts(within:, slots:)
    end
  end

  def initialize(data, ip: nil, helo: nil, mail_from: nil)
    @data = data.gsub(/\r?\n/, "\r\n")
    @ip = ip
    @helo = helo
    @mail_from = mail_from
  end

  def verdicts
    mail_auth.verdicts
  end

  def settled_verdicts(within:, slots: nil)
    mail_auth.settled_verdicts(within:, slots:)
  end

  private
    def mail_auth
      MailAuth.new(@data, ip: @ip, helo: @helo, mail_from: @mail_from)
    end
end
