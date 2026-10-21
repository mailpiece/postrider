require "test_helper"

class RecurringScheduleTest < ActiveSupport::TestCase
  test "every deployed environment schedules the recurring tasks" do
    %w[ production staging ].each do |environment|
      assert_equal schedule.fetch("default"), schedule[environment],
        "config/recurring.yml schedules nothing for #{environment}"
    end
  end

  private
    def schedule
      @schedule ||= YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    end
end
