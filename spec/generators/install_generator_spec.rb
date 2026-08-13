require "rails_helper"
require "rails/generators"
require "generators/rcrewai/rails/install/install_generator"
require "fileutils"

RSpec.describe RcrewAI::Rails::Generators::InstallGenerator do
  let(:destination) { File.expand_path("../../tmp/generator_test", __dir__) }

  before do
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(File.join(destination, "config"))
    File.write(File.join(destination, "config", "routes.rb"), <<~RUBY)
      Rails.application.routes.draw do
      end
    RUBY
  end

  after { FileUtils.rm_rf(destination) }

  # Generators log every created file plus the post-install message to stdout.
  # Swallow it so the spec output stays readable.
  def run_generator
    original = $stdout
    $stdout = StringIO.new
    described_class.start([], destination_root: destination)
  ensure
    $stdout = original
  end

  def migration_paths
    Dir[File.join(destination, "db/migrate/*_create_rcrewai_tables.rb")]
  end

  describe "the initializer" do
    it "creates the initializer" do
      run_generator
      expect(File).to exist(File.join(destination, "config/initializers/rcrewai.rb"))
    end

    it "documents the observation settings in the initializer" do
      run_generator
      content = File.read(File.join(destination, "config/initializers/rcrewai.rb"))
      expect(content).to include("observation_enabled")
      expect(content).to include("observation_capture_prompts")
      expect(content).to include("observation_flush_mode")
      expect(content).to include("observation_retention_days")
    end

    it "configures via RcrewAI::Rails.configure" do
      run_generator
      content = File.read(File.join(destination, "config/initializers/rcrewai.rb"))
      expect(content).to include("RcrewAI::Rails.configure")
    end
  end

  describe "the migration" do
    # The engine registers an `RcrewAI` acronym inflection, so Rails camelizes
    # `create_rcrewai_tables` to `CreateRcrewAITables`, not `CreateRcrewaiTables`.
    # Rails resolves a migration's class from its filename, so a template whose
    # class name disagrees raises NameError on `rails db:migrate` — which is
    # exactly what shipped in 0.7.0. Assert the name Rails will actually look
    # for, derived the same way Rails derives it, rather than hardcoding it.
    it "declares the class name Rails derives from the filename" do
      run_generator
      filename = File.basename(migration_paths.first, ".rb").sub(/\A\d+_/, "")
      expected = ActiveSupport::Inflector.camelize(filename)
      declared = File.read(migration_paths.first)[/class (\w+)/, 1]

      expect(declared).to eq(expected),
                          "Rails will look for #{expected} but the migration declares #{declared}; " \
                          "`rails db:migrate` would raise NameError"
    end

    it "creates a timestamped migration" do
      run_generator
      expect(migration_paths.size).to eq(1)
      expect(File.basename(migration_paths.first)).to match(/\A\d{14}_create_rcrewai_tables\.rb\z/)
    end

    it "creates the spans tables in the migration" do
      run_generator
      content = File.read(migration_paths.first)
      expect(content).to include("create_table :rcrewai_spans")
      expect(content).to include("create_table :rcrewai_span_events")
      expect(content).to include("create_table :rcrewai_crews")
    end

    it "creates every table the engine's models require" do
      run_generator
      content = File.read(migration_paths.first)
      %w[
        rcrewai_crews rcrewai_agents rcrewai_tasks rcrewai_task_assignments
        rcrewai_task_dependencies rcrewai_executions rcrewai_execution_logs
        rcrewai_tools rcrewai_knowledge_sources rcrewai_flow_states
        rcrewai_flow_runs rcrewai_spans rcrewai_span_events
      ].each do |table|
        expect(content).to include("create_table :#{table}"), "expected migration to create #{table}"
      end
    end

    it "subclasses ActiveRecord::Migration" do
      run_generator
      expect(File.read(migration_paths.first)).to match(/class \w+ < ActiveRecord::Migration/)
    end

    it "is valid Ruby" do
      run_generator
      expect(RubyVM::InstructionSequence.compile(File.read(migration_paths.first))).to be_truthy
    end
  end

  describe "the routes" do
    it "mounts the engine in routes" do
      run_generator
      routes = File.read(File.join(destination, "config/routes.rb"))
      expect(routes).to include("mount RcrewAI::Rails::Engine")
    end

    it "does not duplicate the mount when run twice" do
      run_generator
      run_generator
      routes = File.read(File.join(destination, "config/routes.rb"))
      expect(routes.scan(/mount RcrewAI::Rails::Engine/).size).to eq(1)
    end
  end
end
