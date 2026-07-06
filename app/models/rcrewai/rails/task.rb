module RcrewAI
  module Rails
    class Task < ApplicationRecord
      self.table_name = "rcrewai_tasks"
      
      belongs_to :crew
      belongs_to :agent, optional: true
      has_many :task_dependencies, foreign_key: :task_id, dependent: :destroy
      has_many :dependencies, through: :task_dependencies, source: :dependency

      validates :description, presence: true
      validates :expected_output, presence: true

      serialize :context, coder: JSON, type: Array
      serialize :output_json, coder: JSON
      serialize :output_pydantic, coder: JSON
      serialize :tools, coder: JSON, type: Array
      serialize :output_schema, coder: JSON
      serialize :attachments, coder: JSON, type: Array

      scope :ordered, -> { order(:order_index) }

      def to_rcrew_task
        RCrewAI::Task.new(
          name: rcrew_task_name,
          description: description,
          expected_output: expected_output,
          agent: agent&.to_rcrew_agent,
          context: context,
          async: async_execution,
          tools: instantiated_tools,
          callback: callback_method,
          **task_output_options
        )
      end

      # rcrewai 0.4/0.5 task output-processing options. Only emit a key when it
      # is meaningfully set, so an all-default record constructs exactly as it
      # did before these options existed.
      def task_output_options
        opts = {}
        opts[:output_schema] = output_schema.deep_symbolize_keys if output_schema.present?
        opts[:guardrail] = guardrail_callable if guardrail_callable
        opts[:guardrail_max_retries] = guardrail_max_retries if guardrail_callable && guardrail_max_retries
        opts[:output_file] = output_file if output_file.present?
        # Core defaults create_directory to true; only forward when explicitly
        # disabled, so an all-default record still emits nothing.
        opts[:create_directory] = false if create_directory == false
        opts[:markdown] = markdown if markdown
        opts[:attachments] = normalized_attachments if attachments.present?
        opts
      end


      def instantiated_tools
        return [] if tools.blank?

        tools.map do |tool_config|
          tool_class = tool_config["class"].constantize
          tool_params = tool_config["params"] || {}
          tool_class.new(**tool_params.symbolize_keys)
        end
      end

      def add_dependency(other_task)
        task_dependencies.create!(dependency: other_task)
      end

      def remove_dependency(other_task)
        task_dependencies.where(dependency: other_task).destroy_all
      end

      private

      def rcrew_task_name
        return "task_#{id}" if id
        return description.to_s.parameterize.first(40).presence || "task" if description.present?

        "task"
      end

      def callback_method
        return nil unless callback_class.present? && callback_method_name.present?
        
        klass = callback_class.constantize
        ->(output) { klass.new.send(callback_method_name, output) }
      end

      # Resolves guardrail_class + guardrail_method_name to a callable returning
      # the core [ok, value_or_error] contract. Mirrors callback_method. nil when
      # not configured.
      def guardrail_callable
        return nil unless guardrail_class.present? && guardrail_method_name.present?

        klass = guardrail_class.constantize
        ->(output) { klass.new.send(guardrail_method_name, output) }
      end

      # Symbolizes each attachment hash so { "type" => "image", "url" => ... }
      # becomes { type: :image, url: ... } as the core Multimodal builder expects.
      def normalized_attachments
        attachments.map do |att|
          att.symbolize_keys.tap { |h| h[:type] = h[:type].to_sym if h[:type] }
        end
      end
    end
  end
end