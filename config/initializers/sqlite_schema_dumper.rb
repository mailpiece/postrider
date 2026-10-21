# Rails can't dump FTS5 content=/content_rowid=; emit raw CREATE VIRTUAL TABLE SQL.
module SQLiteFTS5SchemaDumperFix
  def virtual_tables(stream)
    virtual_table_sqls = @connection.select_rows(
      "SELECT name, sql FROM sqlite_master WHERE type='table' AND sql LIKE 'CREATE VIRTUAL TABLE%'"
    )

    virtual_table_sqls.each do |table_name, sql|
      stream.puts "  execute #{sql.inspect}"
      stream.puts
    end
  end
end

ActiveSupport.on_load(:active_record_sqlite3adapter) do
  ActiveRecord::ConnectionAdapters::SQLite3::SchemaDumper.prepend(SQLiteFTS5SchemaDumperFix)
end
