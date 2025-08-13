module RcrewAI
  module Rails
    module Tools
      class RailsCacheTool < RCrewAI::Tools::Base
        def initialize
          super(
            name: "Rails Cache Tool",
            description: "Read and write to Rails cache"
          )
        end

        def execute(action, key, value = nil, options = {})
          case action.to_sym
          when :read
            read_cache(key)
          when :write
            write_cache(key, value, options)
          when :delete
            delete_cache(key)
          when :exist?
            cache_exists?(key)
          when :fetch
            fetch_cache(key, options) { value }
          when :clear
            clear_cache
          else
            { error: "Unknown action: #{action}" }
          end
        rescue => e
          { error: "Cache operation failed", message: e.message }
        end

        private

        def read_cache(key)
          value = ::Rails.cache.read(key)
          { key: key, value: value, exists: !value.nil? }
        end

        def write_cache(key, value, options = {})
          success = ::Rails.cache.write(key, value, options)
          { key: key, written: success }
        end

        def delete_cache(key)
          deleted = ::Rails.cache.delete(key)
          { key: key, deleted: deleted }
        end

        def cache_exists?(key)
          exists = ::Rails.cache.exist?(key)
          { key: key, exists: exists }
        end

        def fetch_cache(key, options = {})
          value = ::Rails.cache.fetch(key, options) do
            yield if block_given?
          end
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