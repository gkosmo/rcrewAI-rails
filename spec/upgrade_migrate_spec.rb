require "rails_helper"
require "fileutils"

# Existing installs upgrade by copying the engine's db/migrate files, not by
# re-running the install template. This runs that path: build the previous
# release's schema, then apply only the new migration on top.
#
# Like real_migrate_spec, this swaps the global connection to a throwaway
# in-memory database, so it restores the suite's connection when it is done.
RSpec.describe "upgrading an existing install to rcrewai 0.8 support" do
  let(:engine_root) { File.expand_path("..", __dir__) }
  let(:staging) { File.expand_path("../tmp/upgrade_migrate", __dir__) }

  around do |example|
    suite_config = ActiveRecord::Base.connection_db_config
    example.run
  ensure
    FileUtils.rm_rf(staging)
    ActiveRecord::Base.establish_connection(suite_config)
  end

  it "applies the checkpoint migration on top of the previous schema" do
    FileUtils.rm_rf(staging)
    FileUtils.mkdir_p(staging)

    new_migration = Dir[File.join(engine_root, "db/migrate/012_*.rb")].first
    expect(new_migration).to be_present, "expected a 012_ migration for the 0.8 upgrade"

    conn = ActiveRecord::Base.establish_connection(
      adapter: "sqlite3", database: ":memory:"
    ).lease_connection

    # Step 1: the pre-0.8 schema — the install template minus everything 012
    # adds, which is what an existing 0.7 install actually has.
    template = File.read(
      File.join(engine_root, "lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb")
    )
    pre_0_8 = template
              .gsub(/^\s*t\.boolean :checkpoint_enabled\n/, "")
              .gsub(/^\s*t\.string :run_id\n/, "")
              .gsub(/^\s*t\.string :parent_run_id\n/, "")
              .gsub(/^\s*add_index :rcrewai_executions, :run_id\n/, "")
              .sub(/^\s*create_table :rcrewai_checkpoints do \|t\|.*?^\s*add_index :rcrewai_checkpoints, :parent_run_id\n/m, "")
    File.write(File.join(staging, "20200101000000_create_rcrewai_tables.rb"), pre_0_8)

    ActiveRecord::MigrationContext.new(staging).migrate

    expect(conn.tables).not_to include("rcrewai_checkpoints")
    expect(conn.columns("rcrewai_executions").map(&:name)).not_to include("run_id")

    # Step 2: the upgrade itself.
    FileUtils.cp(new_migration, File.join(staging, "20200102000000_create_rcrewai_checkpoints.rb"))
    expect { ActiveRecord::MigrationContext.new(staging).migrate }.not_to raise_error

    expect(conn.tables).to include("rcrewai_checkpoints")
    expect(conn.columns("rcrewai_executions").map(&:name)).to include("run_id", "parent_run_id")
    expect(conn.columns("rcrewai_crews").map(&:name)).to include("checkpoint_enabled")
  end
end
