require "rails_helper"
require "fileutils"

# Existing installs upgrade by copying the engine's db/migrate files, not by
# re-running the install template. This runs that path: build the previous
# release's schema, then apply only the new migration on top.
#
# Migrations run against an isolated database (see support/isolated_migration),
# so the suite's own connection and schema are never touched.
RSpec.describe "upgrading an existing install to rcrewai 0.8 support" do
  let(:engine_root) { File.expand_path("..", __dir__) }
  let(:staging) { File.expand_path("../tmp/upgrade_migrate", __dir__) }

  after { FileUtils.rm_rf(staging) }

  it "applies the checkpoint migration on top of the previous schema" do
    FileUtils.rm_rf(staging)
    FileUtils.mkdir_p(staging)

    new_migration = Dir[File.join(engine_root, "db/migrate/012_*.rb")].first
    expect(new_migration).to be_present, "expected a 012_ migration for the 0.8 upgrade"

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

    with_isolated_database do |conn|
      migrate_isolated(staging)

      expect(conn.tables).not_to include("rcrewai_checkpoints")
      expect(conn.columns("rcrewai_executions").map(&:name)).not_to include("run_id")

      # Step 2: the upgrade itself.
      FileUtils.cp(new_migration, File.join(staging, "20200102000000_create_rcrewai_checkpoints.rb"))
      expect { migrate_isolated(staging) }.not_to raise_error

      expect(conn.tables).to include("rcrewai_checkpoints")
      expect(conn.columns("rcrewai_executions").map(&:name)).to include("run_id", "parent_run_id")
      expect(conn.columns("rcrewai_crews").map(&:name)).to include("checkpoint_enabled")
    end
  end
end
