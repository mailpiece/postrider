Rails.application.configure do
  config.x.support.email_address = ENV["MAILER_FROM_ADDRESS"].to_s[/[^\s<]+@[^\s>]+/]
end
