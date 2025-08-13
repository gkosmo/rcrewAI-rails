require_relative "lib/rcrewai/rails/version"

Gem::Specification.new do |spec|
  spec.name = "rcrewai-rails"
  spec.version = RcrewAI::Rails::VERSION
  spec.authors = ["gkosmo"]
  spec.email = ["gkosmo1@hotmail.com"]

  spec.summary = "Rails integration for RcrewAI - Build AI agent crews with database persistence and web UI"
  spec.description = <<~DESC
    RcrewAI Rails is a comprehensive Rails engine that brings AI agent orchestration to your Rails applications. 
    Build intelligent AI crews that collaborate to solve complex tasks with full database persistence, 
    background job integration, and a beautiful web dashboard for monitoring and management.

    Features:
    • ActiveRecord models for crews, agents, tasks, and executions with full persistence
    • Rails generators for scaffolding AI crews and agents
    • ActiveJob integration for asynchronous crew execution (works with any Rails background job adapter)
    • Web dashboard with real-time monitoring and management interface
    • Multi-LLM support: OpenAI GPT, Anthropic Claude, Google Gemini, Azure OpenAI, Ollama
    • Production-ready with logging, error handling, and security controls
    • Human-in-the-loop workflows with approval mechanisms
    • Tool ecosystem: web search, file operations, SQL, email, code execution
  DESC
  spec.homepage = "https://github.com/gkosmo/rcrewai-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://gkosmo.github.io/rcrewAI/"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["rubygems_mfa_required"] = "true"

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