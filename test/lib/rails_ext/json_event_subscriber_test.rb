require "test_helper"

class JsonEventSubscriberTest < ActionDispatch::IntegrationTest
  setup do
    @output = StringIO.new
    @subscriber = JsonEventSubscriber.new(@output)
    Rails.event.subscribe(@subscriber)
  end

  teardown do
    Rails.event.unsubscribe(@subscriber)
  end

  test "a request writes one line per event, with who asked" do
    sign_in_as :leo

    get root_path

    line = lines.find { |candidate| candidate["name"] == "action_controller.request_completed" && candidate["payload"]["controller"] == "MailpiecesController" }

    assert_equal 200, line["payload"]["status"]
    assert_equal response.headers["X-Request-Id"], line["context"]["request_id"]
    assert_equal accounts(:davids_account).external_account_id, line["context"]["account_id"]
    assert_equal users(:leo).id, line["context"]["user_id"]
    assert_equal identities(:leo).id, line["context"]["identity_id"]
  end

  test "a delivered message is left out of its line" do
    @subscriber.emit name: "action_mailer.delivered", payload: { message_id: "1@postrider.example", mail: "To: leo@example.com" }

    assert_equal({ "message_id" => "1@postrider.example" }, lines.sole["payload"])
  end

  private
    def lines
      @output.string.lines.map { |line| JSON.parse(line) }
    end
end
