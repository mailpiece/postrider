module MailProvider
  SUFFIXES = {
    ".olc.protection.outlook.com" => "outlook",
    ".yahoodns.net" => "yahoo",
    ".google.com" => "gmail",
    ".googlemail.com" => "gmail"
  }.freeze

  NAMES = { "outlook" => "Outlook.com", "yahoo" => "Yahoo", "gmail" => "Gmail" }.freeze

  class << self
    def for(mx_host)
      SUFFIXES.find { |suffix, _| mx_host.to_s.end_with?(suffix) }&.last
    end

    def label(provider)
      NAMES.fetch(provider, provider)
    end
  end
end
