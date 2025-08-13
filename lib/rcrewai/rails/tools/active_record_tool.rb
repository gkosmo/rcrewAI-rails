module RcrewAI
  module Rails
    module Tools
      class ActiveRecordTool < RCrewAI::Tools::Base
        def initialize(model_class: nil, allowed_methods: [:find, :where, :count])
          @model_class = model_class
          @allowed_methods = allowed_methods
          super(
            name: "ActiveRecord Query Tool",
            description: "Query Rails database using ActiveRecord"
          )
        end

        def execute(query_type, conditions = {})
          validate_query_type!(query_type)
          
          model = get_model_class(conditions.delete(:model) || @model_class)
          
          case query_type.to_sym
          when :find
            model.find(conditions[:id])
          when :find_by
            model.find_by(conditions)
          when :where
            model.where(conditions)
          when :count
            conditions.empty? ? model.count : model.where(conditions).count
          when :pluck
            field = conditions.delete(:field)
            model.where(conditions).pluck(field)
          when :exists?
            model.exists?(conditions)
          when :first
            model.where(conditions).first
          when :last
            model.where(conditions).last
          when :all
            model.where(conditions).to_a
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
          unless @allowed_methods.include?(query_type.to_sym)
            raise ArgumentError, "Query type '#{query_type}' is not allowed"
          end
        end

        def get_model_class(model_name)
          return @model_class if @model_class && model_name.nil?
          
          model_name = model_name.to_s.camelize
          model_name.constantize
        rescue NameError
          raise ArgumentError, "Model class '#{model_name}' not found"
        end
      end
    end
  end
end