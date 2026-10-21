ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "SQLite"
  inflect.acronym "IO"

  inflect.singular "quotas", "quota"
  inflect.plural "quota", "quotas"
end
