module RcrewAI
  module Rails
    module Tools
      class ActiveStorageTool < RCrewAI::Tools::Base
        tool_name "active_storage"
        description "Manage Rails Active Storage attachments: attach, download, analyze, delete, or build a URL."

        param :operation, type: :enum, required: true,
              values: %w[attach download analyze delete url],
              description: "Active Storage operation to perform."
        param :params, type: :object, required: false,
              description: "Operation parameters (model, id, attachment_name, blob_id, signed_id, key, file, filename, content_type, expires_in)."

        def initialize(allowed_operations: %i[attach download analyze])
          super()
          @allowed_operations = allowed_operations.map(&:to_sym)
        end

        def execute(operation:, params: {})
          op = operation.to_sym
          validate_operation!(op)
          opts = (params || {}).transform_keys(&:to_sym)

          case op
          when :attach   then attach_file(opts)
          when :download then download_file(opts)
          when :analyze  then analyze_file(opts)
          when :delete   then delete_file(opts)
          when :url      then get_url(opts)
          else { error: "Unknown operation: #{operation}" }
          end
        rescue => e
          { error: "Active Storage operation failed", message: e.message }
        end

        private

        def validate_operation!(operation)
          return if @allowed_operations.include?(operation)

          raise ArgumentError, "Operation '#{operation}' is not allowed"
        end

        def attach_file(params)
          record = find_record(params[:model], params[:id])
          attachment_name = params[:attachment_name] || :file

          file = params[:file] || params[:io]
          filename = params[:filename] || "attachment"
          content_type = params[:content_type] || "application/octet-stream"

          record.send(attachment_name).attach(
            io: file,
            filename: filename,
            content_type: content_type
          )

          { attached: true, filename: filename, record_id: record.id }
        end

        def download_file(params)
          blob = find_blob(params)

          {
            filename: blob.filename.to_s,
            content_type: blob.content_type,
            byte_size: blob.byte_size,
            data: blob.download
          }
        end

        def analyze_file(params)
          blob = find_blob(params)
          blob.analyze unless blob.analyzed?

          {
            filename: blob.filename.to_s,
            content_type: blob.content_type,
            byte_size: blob.byte_size,
            metadata: blob.metadata,
            analyzed: blob.analyzed?
          }
        end

        def delete_file(params)
          blob = find_blob(params)
          filename = blob.filename.to_s
          blob.purge

          { deleted: true, filename: filename }
        end

        def get_url(params)
          blob = find_blob(params)
          expires_in = params[:expires_in] || 5.minutes

          {
            url: ::Rails.application.routes.url_helpers.rails_blob_url(blob, expires_in: expires_in),
            expires_at: expires_in.from_now
          }
        end

        def find_record(model_name, id)
          model_class = model_name.to_s.camelize.constantize
          model_class.find(id)
        end

        def find_blob(params)
          if params[:blob_id]
            ActiveStorage::Blob.find(params[:blob_id])
          elsif params[:signed_id]
            ActiveStorage::Blob.find_signed(params[:signed_id])
          elsif params[:key]
            ActiveStorage::Blob.find_by!(key: params[:key])
          else
            record = find_record(params[:model], params[:id])
            attachment_name = params[:attachment_name] || :file
            record.send(attachment_name).blob
          end
        end
      end
    end
  end
end
