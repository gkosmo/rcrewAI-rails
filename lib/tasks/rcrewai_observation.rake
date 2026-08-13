namespace :rcrewai do
  namespace :observation do
    desc "Delete observation spans older than the configured retention window"
    task prune: :environment do
      days = ENV.fetch("DAYS", RcrewAI::Rails.config.observation_retention_days).to_i
      removed = RcrewAI::Rails::Observation::Pruner.prune!(older_than_days: days)
      puts "Pruned #{removed} span(s) older than #{days} days."
    end
  end
end
