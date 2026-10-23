ENV["RAILS_ENV"] ||= "test"

ENV["SMTP_LOG_LEVEL"] ||= "FATAL"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "mocha/minitest"

unless [ "0", "false" ].include?(ENV["CI_PROGRESS_BAR"])
  require "minitest/reporters"
  Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new(detailed_skip: false)
end

WebMock.allow_net_connect!

module ActiveSupport
  class TestCase
    parallelize workers: :number_of_processors, work_stealing: ENV["WORK_STEALING"] != "false"

    fixtures :all

    include ActiveJob::TestHelper
    include DnsTestHelper, EnvTestHelper, DomainTestHelper, MailAuthTestHelper

    def perform_enqueued_jobs(...)
      saved_account, saved_user = Current.account, Current.user
      Current.account = Current.user = nil
      super
    ensure
      Current.account, Current.user = saved_account, saved_user
    end

    setup do
      Current.account = accounts(:davids_account)
      stub_mailauth
    end

    teardown do
      Current.clear_all
    end
  end
end

module ActionDispatch
  class IntegrationTest
    include SessionTestHelper

    setup do
      integration_session.default_url_options = integration_session.default_url_options.merge(script_name: "/#{accounts(:davids_account).external_account_id}")
    end

    def bearer_token_env(token)
      { "HTTP_AUTHORIZATION" => "Bearer #{token}" }
    end

    def api_token_env
      bearer_token_env("test_token_davids_api_0000000000")
    end

    def sending_token_env(token = DomainTestHelper::SENDING_TOKEN)
      bearer_token_env(token)
    end

    def default_sending_token
      sending_tokens(:example)
    end

    def account_path(path)
      "/#{accounts(:davids_account).external_account_id}#{path}"
    end
  end
end

class ActionDispatch::SystemTestCase
  setup do
    self.default_url_options = default_url_options.merge(script_name: "/#{accounts(:davids_account).external_account_id}")
  end
end

ActiveSupport.on_load(:active_record_fixture_set) do
  prepend(FixtureUuidTestHelper)
end
