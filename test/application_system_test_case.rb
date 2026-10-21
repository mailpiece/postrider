require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  browser_options = Selenium::WebDriver::Chrome::Options.new.tap do |opts|
    opts.add_argument("--window-size=1200,800")
    opts.add_argument("--disable-extensions")
    # Keep background tabs at full priority
    opts.add_argument("--disable-renderer-backgrounding")
    # Don't treat an occluded window's foreground tab as backgrounded
    opts.add_argument("--disable-backgrounding-occluded-windows")
    # Auto-deny permission prompts
    opts.add_argument("--deny-permission-prompts")
    opts.add_argument("--enable-automation")

    # Apple Silicon containers may point this at Chromium (no arm64 Chrome build).
    opts.binary = ENV["CHROME_BINARY"] if ENV["CHROME_BINARY"]
  end

  Capybara.register_driver :chrome_headless do |app|
    browser_options.add_argument("--headless")
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
  end

  Capybara.register_driver :chrome do |app|
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
  end

  if ENV["SYSTEM_TESTS_BROWSER"]
    driven_by :chrome, screen_size: [ 1200, 1000 ]
  else
    driven_by :chrome_headless, screen_size: [ 1200, 1000 ]
  end

  private
    def sign_in_as(user)
      visit session_transfer_url(user.identity.transfer_id, script_name: nil)
      assert_current_path root_path
    end
end
