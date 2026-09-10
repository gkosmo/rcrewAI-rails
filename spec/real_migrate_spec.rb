require "rails_helper"
require "rails/generators"
require "generators/rcrewai/rails/install/install_generator"
require "fileutils"

RSpec.describe "running the generated migration the way Rails does" do
  let(:destination) { File.expand_path("../tmp/real_migrate", __dir__) }

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(File.join(destination, "config"))
    File.write(File.join(destination, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")
    original = $stdout
    $stdout = StringIO.new
    begin
      RcrewAI::Rails::Generators::InstallGenerator.start([], destination_root: destination)
    ensure
      $stdout = original
    end
  end

  after { FileUtils.rm_rf(destination) }

  it "migrates without raising NameError" do
    migration_dir = File.join(destination, "db/migrate")

    with_isolated_database do |conn|
      # MigrationContext resolves each migration's class from its filename via
      # the active inflections — the exact step a hand-rolled `load` +
      # constant call skips, and the step that raised NameError in 0.7.0.
      expect { migrate_isolated(migration_dir) }.not_to raise_error

      tables = conn.tables.grep(/rcrewai/)
      expect(tables).to include("rcrewai_crews", "rcrewai_spans", "rcrewai_span_events", "rcrewai_tools",
                                "rcrewai_checkpoints")

      # rcrewai 0.8 checkpointing columns.
      expect(conn.columns("rcrewai_executions").map(&:name)).to include("run_id", "parent_run_id")
      expect(conn.columns("rcrewai_crews").map(&:name)).to include("checkpoint_enabled")
    end
  end
end
