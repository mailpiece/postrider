require "test_helper"

class ActionMailerDeliveredEventWithoutMailTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  TOKEN = "madeUpForwardingToken000"

  setup do
    ActionMailer::Base # loads its log subscriber
    @log = StringIO.new
    @logger, ActionMailer::LogSubscriber.logger = ActionMailer::LogSubscriber.logger, ActiveSupport::Logger.new(@log)
  end

  teardown do
    ActionMailer::LogSubscriber.logger = @logger
  end

  test "a delivered mail is logged without its content and delivered with it" do
    events = []
    subscriber = Class.new { define_method(:emit) { |event| events << event } }.new
    Rails.event.subscribe(subscriber) { |event| event[:name] == "action_mailer.delivered" }

    assert_emails 1 do
      MailboxMailer.forward_confirmation(mailbox: mailboxes(:forwarding), token: TOKEN).deliver_now
    end

    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, TOKEN, "delivery should receive the original mail"
    assert_includes ActionMailer::Base.deliveries.last.encoded, TOKEN
    assert_includes @log.string, "Delivered mail"
    assert_no_match TOKEN, @log.string
    assert_equal [ ActionMailerDeliveredEventWithoutMail::FILTERED ], events.map { |event| event[:payload][:mail] }
  ensure
    Rails.event.unsubscribe(subscriber)
  end

  test "the filter runs ahead of every other delivery consumer from boot" do
    listeners = ActiveSupport::Notifications.notifier.listeners_for("deliver.action_mailer")

    assert_same ActionMailerDeliveredEventWithoutMail::SUBSCRIBER, listeners.first
    assert listeners.many?, "Rails' own mail subscribers should follow it"
  end
end
