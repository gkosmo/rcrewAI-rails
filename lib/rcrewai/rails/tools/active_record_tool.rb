module RcrewAI
  module Rails
    module Tools
      class ActiveRecordTool < RCrewAI::Tools::Base
        tool_name "active_record_query"
        description "Query the Rails database using ActiveRecord. Supports find, find_by, where, count, pluck, exists?, first, last, and all."

        param :query_type, type: :enum, required: true,
              values: %w[find find_by where count pluck exists? first last all],
              description: "ActiveRecord query method to invoke."
        param :model, type: :string, required: false,
              description: "Model class name (e.g. 'User'). Defaults to the model configured on the tool."
        param :conditions, type: :object, required: false,
              description: "Query conditions as a hash. For :find, include :id. For :pluck, include :field."

        def initialize(model_class: nil, allowed_methods: %i[find where count])
          super()
          @model_class = model_class
          @allowed_methods = allowed_methods.map(&:to_sym)
        end

        def execute(query_type:, model: nil, conditions: {})
          query_type = query_type.to_sym
          validate_query_type!(query_type)

          model_klass = resolve_model_class(model)
          conds = (conditions || {}).transform_keys(&:to_sym)

          case query_type
          when :find
            model_klass.find(conds[:id])
          when :find_by
            model_klass.find_by(conds)
          when :where
            model_klass.where(conds)
          when :count
            conds.empty? ? model_klass.count : model_klass.where(conds).count
          when :pluck
            field = conds.delete(:field)
            model_klass.where(conds).pluck(field)
          when :exists?
            model_klass.exists?(conds)
          when :first
            model_klass.where(conds).first
          when :last
            model_klass.where(conds).last
          when :all
            model_klass.where(conds).to_a
          else
            raise ArgumentError, "Unsupported query type: #{query_type}"
          end
        rescue ActiveRecord::RecordNotFound => e
          { error: "Record not found", message: e.message }
        rescue => e
          { error: "Query failed", message: e.message }
        end

        private

        def validate_query_type!(query_type)
          return if @allowed_methods.include?(query_type)

          raise ArgumentError, "Query type '#{query_type}' is not allowed"
        end

        def resolve_model_class(model_name)
          return @model_class if model_name.nil? && @model_class
          raise ArgumentError, "No model specified" if model_name.nil?

          model_name.to_s.camelize.constantize
        rescue NameError
          raise ArgumentError, "Model class '#{model_name}' not found"
        end
      end
    end
  end
end
