require "rails_helper"

RSpec.describe "access to the engine", type: :request do
  def config = RcrewAI::Rails.config

  # Every route the engine draws, so a new controller can't be missed.
  ROUTES = RcrewAI::Rails::Engine.routes.routes.filter_map do |route|
    path = route.path.spec.to_s.sub("(.:format)", "").gsub(/:\w+/, "1")
    next if route.app.engine? rescue nil

    [route.verb, "/rcrewai#{path}"] if route.verb.present?
  end.uniq

  it "knows of the routes it is checking" do
    expect(ROUTES.map(&:last)).to include("/rcrewai/crews", "/rcrewai/api/v1/crews", "/rcrewai/api/v1/crews/1/execute",
                                          "/rcrewai/executions/1/observation", "/rcrewai/agents/1/tools")
  end

  describe "with no hook configured" do
    before { config.authenticate_with = nil }

    ROUTES.each do |verb, path|
      it "refuses #{verb} #{path} outside development" do
        public_send(verb.downcase, path)
        expect(response).to have_http_status(:forbidden)
      end
    end

    it "does not create a crew through the API" do
      expect { post "/rcrewai/api/v1/crews", params: { crew: { name: "anon" } } }
        .not_to(change(RcrewAI::Rails::Crew, :count))
    end

    it "does not run a crew through the API" do
      crew = RcrewAI::Rails::Crew.create!(name: "c")
      expect(RcrewAI::Rails::CrewExecutionJob).not_to receive(:perform_later)

      post "/rcrewai/api/v1/crews/#{crew.id}/execute"
      expect(response).to have_http_status(:forbidden)
    end

    it "says what to configure" do
      get "/rcrewai/crews"
      expect(response.body).to include("authenticate_with")
    end

    it "allows access in development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
      get "/rcrewai/crews"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "with a hook configured" do
    it "lets the request through when it answers truthy" do
      config.authenticate_with = ->(_controller) { :a_user }
      get "/rcrewai/crews"
      expect(response).to have_http_status(:ok)
    end

    [false, nil].each do |answer|
      it "refuses the request when it answers #{answer.inspect}" do
        config.authenticate_with = ->(_controller) { answer }
        get "/rcrewai/crews"
        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include("authenticate_with")
      end
    end

    it "keeps the response the hook gave, such as a redirect to sign in" do
      config.authenticate_with = ->(controller) { controller.redirect_to("/sign_in") }
      get "/rcrewai/crews"
      expect(response).to redirect_to("/sign_in")
    end

    it "gives the hook the controller, so it can read the request and session" do
      seen = nil
      config.authenticate_with = lambda do |controller|
        seen = controller.request.path
        true
      end
      get "/rcrewai/api/v1/crews"
      expect(seen).to eq("/rcrewai/api/v1/crews")
    end

    it "also runs on the API" do
      config.authenticate_with = ->(_controller) { false }
      get "/rcrewai/api/v1/crews"
      expect(response).to have_http_status(:forbidden)
    end

    it "still honours the web UI switch" do
      config.enable_web_ui = false
      get "/rcrewai/crews"
      expect(response.body).to include("disabled")
    ensure
      config.enable_web_ui = true
    end
  end

  describe "the Action Cable mount" do
    it "is not part of the engine, so nothing reaches cable behind the auth hook's back" do
      paths = RcrewAI::Rails::Engine.routes.routes.map { |r| r.path.spec.to_s }
      expect(paths.grep(/cable/)).to be_empty
    end
  end
end
