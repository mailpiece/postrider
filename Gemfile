source "https://rubygems.org"

gem "rails", github: "rails/rails", branch: "main"

# Assets & front end
gem "importmap-rails"
gem "propshaft"
gem "stimulus-rails"
gem "turbo-rails", github: "hotwired/turbo-rails", branch: "offline-cache"

# Deployment and drivers
gem "bootsnap", require: false
gem "kamal", require: false
gem "puma", "~> 8.0"
gem "solid_cable", ">= 3.0"
gem "solid_cache", "~> 1.0"
gem "solid_queue", "~> 1.5"
gem "sqlite3", ">= 2.9.6"
gem "thruster", require: false
gem "tzinfo-data"

# Features
gem "bcrypt", "~> 3.1.22"
gem "geared_pagination", "~> 1.2"
gem "rqrcode"
gem "jbuilder"
gem "platform_agent"
gem "surfguard", github: "basecamp/surfguard" # The SSRF address policy behind webhook and outbound delivery

# Operations
gem "autotuner"
gem "mission_control-jobs"
gem "stackprof"
gem "benchmark" # indirect dependency, being removed from Ruby 3.5 stdlib so here to quash warnings

group :development, :test do
  gem "brakeman", require: false
  gem "bundler-audit", require: false
  gem "debug"
  gem "faker"
  gem "rack-mini-profiler"
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "minitest-reporters", require: false
  gem "mocha"
  gem "selenium-webdriver"
  gem "webmock"
end

gem "base64" # required on Ruby >= 3.4, dropped from default gems

gem "acme-client"

# Mail Server Engine
gem "mailauth", github: "mailpiece/mailauth", branch: "main"
gem "mailbounce", github: "mailpiece/mailbounce", branch: "main"
gem "mailreport", github: "mailpiece/mailreport", branch: "main"
gem "mailresolver", github: "mailpiece/mailresolver", branch: "main"
gem "mailsmtp", github: "mailpiece/mailsmtp", branch: "main"
gem "mailverp", github: "mailpiece/mailverp", branch: "main"
gem "mta_sts", github: "mailpiece/mta_sts", branch: "main"
gem "filter_path_parameters", github: "mailpiece/filter_path_parameters", branch: "main"
