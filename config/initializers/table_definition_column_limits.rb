# Default string/text limits to MySQL-compatible sizes so SQLite matches production schemas.
module TableDefinitionColumnLimits
  TEXT_SIZE_TO_LIMIT = {
    tiny: 255,
    medium: 16_777_215,
    long: 4_294_967_295
  }.freeze

  TEXT_DEFAULT_LIMIT = 65_535
  STRING_DEFAULT_LIMIT = 255

  def column(name, type, **options)
    if type == :string
      options[:limit] ||= STRING_DEFAULT_LIMIT
    end

    if type == :text || type == :binary
      if options.key?(:size)
        size = options.delete(:size)
        options[:limit] ||= TEXT_SIZE_TO_LIMIT.fetch(size) do
          raise ArgumentError, "Unknown text size: #{size.inspect}. Use :tiny, :medium, or :long"
        end
      elsif type == :text
        options[:limit] ||= TEXT_DEFAULT_LIMIT
      end
    end

    super
  end
end

# SQLite ignores VARCHAR/TEXT length; enforce with CHECK constraints.
module SQLiteColumnLimitCheckConstraints
  def add_column_options!(sql, options)
    super

    column = options[:column]
    if column && column.limit && %i[string text].include?(column.type)
      check_expr = if column.type == :string
        # VARCHAR limits are in characters
        %(length("#{column.name}") <= #{column.limit})
      else
        # TEXT limits are in bytes
        %(length(CAST("#{column.name}" AS BLOB)) <= #{column.limit})
      end
      sql << " CHECK(#{check_expr})"
    end

    sql
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::ConnectionAdapters::TableDefinition.prepend(TableDefinitionColumnLimits)
end

ActiveSupport.on_load(:active_record_sqlite3adapter) do
  ActiveRecord::ConnectionAdapters::SQLite3::SchemaCreation.prepend(SQLiteColumnLimitCheckConstraints)
end
