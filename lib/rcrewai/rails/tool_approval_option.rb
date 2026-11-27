module RcrewAI
  module Rails
    # Raised for a setting the installed rcrewai can't honour.
    class UnsupportedOption < StandardError; end

    # rcrewai accepts require_approval_for_tools before 0.12, but runs tools
    # without asking. Building such an agent is refused instead.
    module ToolApprovalOption
      module_function

      def options(required)
        return {} unless required

        unless defined?(RCrewAI::ToolApproval)
          raise UnsupportedOption,
                "require_approval_for_tools needs rcrewai 0.12 or later; #{RCrewAI::VERSION} " \
                "runs tools without asking"
        end

        { require_approval_for_tools: true }
      end
    end
  end
end
