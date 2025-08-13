require_relative "lib/rcrewai/rails/version"

Gem::Specification.new do |spec|
  spec.name = "rcrewai-rails"
  spec.version = RcrewAI::Rails::VERSION
  spec.authors = ["gkosmo"]
  spec.email = ["gkosmo1@hotmail.com"]

  spec.summary = "Rails integration for RcrewAI - AI agent orchestration framework"
  spec.description = "A Rails engine that provides ActiveRecord persistence, background job integration, generators, and web UI for RcrewAI crews and agents"
  spec.homepage = "https://github.com/gkosmo/rcrewai-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependency
  spec.add_dependency "rcrewai", "~> 0.2"
  
  # Rails dependencies
  spec.add_dependency "rails", ">= 7.0.0"
  spec.add_dependency "activerecord", ">= 7.0.0"
  spec.add_dependency "activejob", ">= 7.0.0"
  spec.add_dependency "actionview", ">= 7.0.0"
  
  # Web UI dependencies (optional, but commonly used)
  spec.add_dependency "turbo-rails", "~> 2.0"
  spec.add_dependency "stimulus-rails", "~> 1.0"
  
  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "factory_bot_rails", "~> 6.0"
  spec.add_development_dependency "sqlite3", "~> 1.4"
end