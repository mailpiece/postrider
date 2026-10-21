class SmtpSession < MailSmtp::Session
  attr_accessor :junk_commands

  def initialize
    super
    @junk_commands = 0
  end
end
