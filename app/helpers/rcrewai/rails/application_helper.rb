module RcrewAI
  module Rails
    module ApplicationHelper
      # Subscribes the page to live updates. Without Action Cable the host has no
      # way to deliver them, so the page just doesn't update by itself.
      def rcrewai_stream_from(*streamables)
        turbo_stream_from(*streamables) if defined?(::ActionCable::Engine)
      end

      # Tells Turbo where the host serves Action Cable, which may not be /cable.
      def rcrewai_cable_meta_tag
        action_cable_meta_tag if respond_to?(:action_cable_meta_tag)
      end
    end
  end
end
