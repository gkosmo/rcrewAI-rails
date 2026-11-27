module RcrewAI
  module Rails
    # rcrewai before the harness ignores a harness: option, which would leave
    # every tool unchecked. Asking for one there is refused instead.
    module HarnessOption
      module_function

      def supported?
        defined?(RCrewAI::Harness) ? true : false
      end

      def require_support!
        return if supported?

        raise UnsupportedOption,
              "a harness needs a newer rcrewai than #{RCrewAI::VERSION}, which would run tools without it"
      end

      # The agent options for +harness+; nil or false means none.
      def options(harness)
        return {} unless harness

        require_support!
        { harness: harness }
      end

      # What config.agent_harness gives an engine agent record. Support is
      # checked before the hook runs, because on an older rcrewai the hook
      # can't build a harness at all.
      def for_record(record, hook = RcrewAI::Rails.config.agent_harness)
        return {} unless hook

        require_support!
        options(hook.call(record))
      end
    end
  end
end
