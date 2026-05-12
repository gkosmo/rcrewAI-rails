module RcrewAI
  module Rails
    module Tools
      class RailsCacheTool < RCrewAI::Tools::Base
        tool_name "rails_cache"
        description "Read from and write to the Rails cache. Supports read, write, delete, exist?, fetch, and clear."

        param :action, type: :enum, required: true,
              values: %w[read write delete exist? fetch clear],
              description: "Cache action to perform."
        param :key, type: :string, required: false,
              description: "Cache key. Required for every action except clear."
        param :value, type: :string, required: false,
              description: "Value to store (used by write and fetch fallback)."
        param :options, type: :object, required: false,
              description: "Cache options hash (e.g. expires_in)."

        def execute(action:, key: nil, value: nil, options: {})
          act = action.to_sym
          opts = (options || {}).transform_keys(&:to_sym)

          case act
          when :read    then read_cache(key)
          when :write   then write_cache(key, value, opts)
          when :delete  then delete_cache(key)
          when :exist?  then cache_exists?(key)
          when :fetch   then fetch_cache(key, value, opts)
          when :clear   then clear_cache
          else { error: "Unknown action: #{action}" }
          end
        rescue => e
          { error: "Cache operation failed", message: e.message }
        end

        private

        def read_cache(key)
          value = ::Rails.cache.read(key)
          { key: key, value: value, exists: !value.nil? }
        end

        def write_cache(key, value, options)
          success = ::Rails.cache.write(key, value, options)
          { key: key, written: success }
        end

        def delete_cache(key)
          deleted = ::Rails.cache.delete(key)
          { key: key, deleted: deleted }
        end

        def cache_exists?(key)
          { key: key, exists: ::Rails.cache.exist?(key) }
        end

        def fetch_cache(key, fallback, options)
          value = ::Rails.cache.fetch(key, options) { fallback }
          { key: key, value: value }
        end

        def clear_cache
          ::Rails.cache.clear
          { cleared: true }
        end
      end
    end
  end
end
