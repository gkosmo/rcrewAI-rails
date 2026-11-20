module RcrewAI
  module Rails
    # Turns a stored class name into a tool, for names the host has allowed.
    # Names come from forms and database rows, so nothing else gets loaded:
    # the name is compared as a string before constantize sees it.
    module ToolAllowlist
      class NotAllowed < StandardError; end

      module_function

      def allowed?(name)
        RcrewAI::Rails.config.allowed_tool_classes.map(&:to_s).include?(name.to_s)
      end

      def build(name, params = {})
        unless allowed?(name)
          raise NotAllowed, "Tool class #{name.to_s.inspect} is not in RcrewAI::Rails.config.allowed_tool_classes"
        end

        params = JSON.parse(params) if params.is_a?(String) && params.present?
        name.to_s.constantize.new(**(params.presence || {}).to_h.symbolize_keys)
      end
    end
  end
end
