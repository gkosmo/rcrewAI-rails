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

    conn = ActiveRecord::Base.establish_connection(
      adapter: "sqlite3", database: ":memory:"
    ).lease_connection

    # MigrationContext resolves each migration's class from its filename via the
    # active inflections — the exact step a hand-rolled `load` + constant call
    # skips, and the step that raised NameError in 0.7.0.
    context = ActiveRecord::MigrationContext.new(migration_dir)
    expect { context.migrate }.not_to raise_error

    tables = conn.tables.grep(/rcrewai/)
    expect(tables).to include("rcrewai_crews", "rcrewai_spans", "rcrewai_span_events", "rcrewai_tools")
  end
end
