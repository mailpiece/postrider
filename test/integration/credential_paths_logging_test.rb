require "test_helper"

class CredentialPathsLoggingTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:davids_account)
    @join_code = account_join_codes(:davids_account)
  end

  test "a join link is logged with its code filtered" do
    log = capture_log do
      get join_path(code: @join_code.code, script_name: @account.slug)
    end

    assert_response :success
    assert_includes log, "/join/[FILTERED]"
    assert_not_includes log, @join_code.code
  end

  private
    def capture_log
      output = StringIO.new
      logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(output)
      yield
      output.string
    ensure
      Rails.logger = logger
    end
end
