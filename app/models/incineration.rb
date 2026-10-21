class Incineration < ApplicationRecord
  belongs_to :incinerable, polymorphic: true
end
