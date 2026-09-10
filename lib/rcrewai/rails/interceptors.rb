# frozen_string_literal: true

module RcrewAI
  module Rails
    # Applies the configured LLM interceptor hooks (rcrewai 0.8+) to a client.
    #
    # The gem forwards +before_request:+/+after_response:+ only through
    # LLMClient.for_provider. Agents build their client via LLMClient.resolve,
    # which does not, so hooks configured on the engine would never reach a
    # per-agent client. Registering them on the built client instead covers
    # every path uniformly.
    module Interceptors
      module_function

      # Registers the configured hooks on +client+ and returns it.
      #
      # A client the host supplied ready-made (anything not speaking the hook
      # API, e.g. a bare double or a custom object responding only to #chat)
      # is returned untouched rather than raising -- the gem accepts any
      # object responding to #chat as an llm, and instrumentation must never
      # be the reason a run fails.
      def apply(client, config = RcrewAI::Rails.config)
        return client unless client

        Array(config.llm_before_request).each do |hook|
          client.before_request(hook) if client.respond_to?(:before_request)
        end

        Array(config.llm_after_response).each do |hook|
          client.after_response(hook) if client.respond_to?(:after_response)
        end

        client
      end

      # True when any interceptor is configured, so callers can skip the work
      # entirely in the common case where none are.
      def configured?(config = RcrewAI::Rails.config)
        Array(config.llm_before_request).any? || Array(config.llm_after_response).any?
      end

      # Registers the hooks on an already-built agent's client.
      def apply_to_agent(agent, config = RcrewAI::Rails.config)
        return agent unless configured?(config)
        return agent unless agent.respond_to?(:llm_client)

        apply(agent.llm_client, config)
        agent
      end
    end
  end
end
