require "spec_helper"
require "json"
require "tmpdir"
require "open3"
require "fileutils"

# Generates real Rails apps and runs the documented command in them. Slow, so
# one example builds each host; skip with `rspec --tag ~host_app`.
RSpec.describe "installing into a real host app", :host_app do
  ENGINE_ROOT = File.expand_path("../..", __dir__)
  PROBE = File.join(__dir__, "support/host_probe.rb")
  SUITE_GEMFILE = ENV.fetch("BUNDLE_GEMFILE", File.join(ENGINE_ROOT, "Gemfile"))
  # The Rails this suite resolved, so the hosts match it.
  RAILS_VERSION = Gem.loaded_specs.fetch("railties").version.to_s

  def sh(*cmd, dir:, env: {})
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e({ "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }.merge(env), *cmd, chdir: dir)
    end
    [output, status]
  end

  def sh!(*cmd, dir:, env: {})
    output, status = sh(*cmd, dir: dir, env: env)
    raise "#{cmd.join(' ')} failed:\n#{output}" unless status.success?

    output
  end

  # A minimal host with only what the engine needs, plus any extra gems.
  def build_host(dir, extra_gems: "")
    Bundler.with_original_env do
      output, status = Open3.capture2e(
        { "BUNDLE_GEMFILE" => SUITE_GEMFILE },
        "bundle", "exec", "rails", "new", dir, "--skip-bundle", "--skip-git", "--skip-test", "--skip-system-test",
        "--skip-javascript", "--skip-docker", "--skip-kamal", "--skip-rubocop", "--skip-brakeman", "--skip-ci",
        "--skip-devcontainer", "--skip-bootsnap", "--skip-asset-pipeline", chdir: ENGINE_ROOT
      )
      raise "rails new failed:\n#{output}" unless status.success?
    end

    File.write(File.join(dir, "Gemfile"), <<~GEMFILE)
      source "https://rubygems.org"
      gem "rails", "#{RAILS_VERSION}"
      gem "sqlite3", ">= 1.4"
      gem "rcrewai-rails", path: "#{ENGINE_ROOT}"
      #{extra_gems}
    GEMFILE
    sh!("bundle", "install", "--prefer-local", "--quiet", dir: dir)
  end

  def install_and_probe(dir)
    generate = sh!("bin/rails", "generate", "rcrewai:rails:install", dir: dir, env: { "RAILS_ENV" => "test" })
    # This command exits 0 even when it can't find the generator.
    raise generate if generate.include?("Could not find generator")

    crew = sh!("bin/rails", "generate", "rcrewai:rails:crew", "research_team", "sequential", dir: dir, env: { "RAILS_ENV" => "test" })
    raise crew unless File.exist?(File.join(dir, "app/crews/research_team_crew.rb"))

    sh!("bin/rails", "db:migrate", dir: dir, env: { "RAILS_ENV" => "test" })
    probe = sh!("bin/rails", "runner", PROBE, dir: dir, env: { "RAILS_ENV" => "test" })
    [generate, JSON.parse(probe[/^PROBE:(.*)$/, 1])]
  end

  def expect_safe_and_rendering(results)
    expect(results["anonymous"].values).to all(eq(403)), "anonymous requests: #{results['anonymous']}"
    expect(results["crews_after_anonymous"]).to eq(1)
    expect(results["signed_in"]).to eq("dashboard" => 200, "execution" => 200)

    expect(results["page"]).not_to match(%r{(src|href)="[^"]*application[^"]*"})
    expect(results["assets"].values.map { |a| a["status"] }).to all(eq(200))
    expect(results["assets"].values.map { |a| a["type"] }).to contain_exactly("text/css", "text/javascript")
    expect(results["turbo_js"]).to be(true)

    expect(results["live_page"]).to include("<turbo-cable-stream-source")
    expect(results["page"]).to include('name="action-cable-url"')
  end

  it "installs with the documented command on a host without Sprockets, such as Webpacker" do
    Dir.mktmpdir("rcrewai-host") do |tmp|
      dir = File.join(tmp, "host")
      build_host(dir)
      expect(File.read(File.join(dir, "Gemfile"))).not_to include("sprockets")

      generate, results = install_and_probe(dir)

      expect(generate).to include("config/initializers/rcrewai.rb")
      expect(File.read(File.join(dir, "config/routes.rb"))).to include("mount RcrewAI::Rails::Engine")
      expect_safe_and_rendering(results)
    end
  end

  it "renders on a Sprockets host whose manifest has no application.js" do
    Dir.mktmpdir("rcrewai-host") do |tmp|
      dir = File.join(tmp, "host")
      build_host(dir, extra_gems: 'gem "sprockets-rails", require: "sprockets/railtie"')
      FileUtils.mkdir_p(File.join(dir, "app/assets/config"))
      File.write(File.join(dir, "app/assets/config/manifest.js"), "//= link_tree ../images\n")

      _generate, results = install_and_probe(dir)

      expect_safe_and_rendering(results)
    end
  end
end
