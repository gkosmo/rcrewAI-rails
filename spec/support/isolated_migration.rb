# frozen_string_literal: true

# Runs migrations against a throwaway database without disturbing the suite's.
#
# The test database is sqlite3 ":memory:" and Combustion loads the schema into
# it once at boot. Calling ActiveRecord::Base.establish_connection replaces that
# pool, and reconnecting yields an *empty* memory database -- the schema cannot
# be rebuilt -- so every later example loses its tables. That made the suite
# order-dependent: it passed in defined order only because the migration specs
# happened to run last.
#
# Instead of swapping the global connection, migrations run against a separate
# abstract class with its own pool, entered via +connected_to+. Migrations
# resolve their connection through ActiveRecord::Base, so the block also swaps
# Base's connection for its duration and restores it afterwards.
module IsolatedMigration
  # A connection handler of its own, so leasing here cannot disturb the suite.
  class Sandbox < ActiveRecord::Base
    self.abstract_class = true
  end

  # Yields a connection to a fresh, empty database. Everything done inside the
  # block -- migrating, inspecting tables -- happens against it.
  #
  # Migrations resolve their pool through
  # ActiveRecord::Tasks::DatabaseTasks.migration_class (Rails 7.1+), so
  # pointing that at the sandbox is the supported way to redirect them without
  # touching ActiveRecord::Base's own connection.
  def with_isolated_database
    Sandbox.establish_connection(adapter: "sqlite3", database: ":memory:")

    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:migration_class).and_return(Sandbox)

    Sandbox.connection_pool.with_connection { |conn| yield conn }
  ensure
    Sandbox.remove_connection
  end

  # Migrates +dir+ against the sandbox connection, recording versions in that
  # database rather than the suite's schema_migrations table.
  def migrate_isolated(dir)
    ActiveRecord::MigrationContext.new(
      dir,
      Sandbox.connection_pool.schema_migration,
      Sandbox.connection_pool.internal_metadata
    ).migrate
  end
end

RSpec.configure { |config| config.include IsolatedMigration }
