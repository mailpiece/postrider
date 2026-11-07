require "test_helper"

class ColumnLimitsTest < ActiveSupport::TestCase
  test "SQLite limit constraints are added without deprecation warnings" do
    assert_not_deprecated(ActiveRecord.deprecator) do
      ActiveRecord::Base.connection.create_table(:widgets, temporary: true) { |t| t.string :name, limit: 10 }
    end
  end
end
