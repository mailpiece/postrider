module User::Named
  extend ActiveSupport::Concern

  included do
    scope :alphabetically, -> { order("lower(name)") }
  end

  def first_name
    name.split(/\s/).first
  end

  def initials
    name.scan(/\b\p{L}/).join.upcase
  end
end
