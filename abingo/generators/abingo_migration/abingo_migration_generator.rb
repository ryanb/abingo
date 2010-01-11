class AbingoMigrationGenerator < Rails::Generator::Base
  def manifest
    record do |m|
      m.migration_template 'abingo_migration.rb', 'db/migrate'
    end
  end

  def file_name
    "abingo_migration"
  end
end
