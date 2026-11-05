# Runs inside a generated host app with `bin/rails runner`. Makes real requests
# through the host's middleware and prints what a browser would have seen.
require "json"

results = {}
session = ActionDispatch::Integration::Session.new(Rails.application)
session.host!("localhost")

fetch = lambda do |method, path, **opts|
  session.public_send(method, path, **opts)
  { status: session.response.status, body: session.response.body, type: session.response.media_type }
rescue StandardError => e
  { status: "raised #{e.class}: #{e.message.lines.first}", body: "", type: nil }
end

crew = RcrewAI::Rails::Crew.create!(name: "probe")
execution = crew.executions.create!(status: "running", started_at: Time.current)

routes = {
  "dashboard" => [:get, "/rcrewai"],
  "crews" => [:get, "/rcrewai/crews"],
  "execution" => [:get, "/rcrewai/executions/#{execution.id}"],
  "api_crews" => [:get, "/rcrewai/api/v1/crews"],
  "api_create" => [:post, "/rcrewai/api/v1/crews", { params: { crew: { name: "anon" } } }]
}

anonymous = routes.transform_values { |(method, path, opts)| fetch.call(method, path, **(opts || {}))[:status] }
results["anonymous"] = anonymous
results["crews_after_anonymous"] = RcrewAI::Rails::Crew.count

RcrewAI::Rails.config.authenticate_with = ->(_controller) { true }
page = fetch.call(:get, "/rcrewai")
live = fetch.call(:get, "/rcrewai/executions/#{execution.id}")
results["signed_in"] = { "dashboard" => page[:status], "execution" => live[:status] }
results["page"] = page[:body]
results["live_page"] = live[:body]

results["assets"] = page[:body].scan(%r{(?:src|href)="([^"]*/assets/[^"]*)"}).flatten.to_h do |path|
  asset = fetch.call(:get, path)
  [path, { "status" => asset[:status], "type" => asset[:type], "bytes" => asset[:body].bytesize }]
end
results["turbo_js"] = results["assets"].keys.grep(/turbo/).first&.then { |path| fetch.call(:get, path)[:body] }.to_s.include?("turbo-cable-stream-source")

puts "PROBE:#{results.to_json}"
