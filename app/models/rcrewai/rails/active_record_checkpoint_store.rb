module RcrewAI
  module Rails
    # Persists rcrewai crew checkpoints to the DB. Implements the core
    # checkpoint-store contract: save(id, record) / load(id) => record or nil /
    # list => ids / delete(id). Pass an instance as +checkpoint:+ to
    # RCrewAI::Crew#execute or #resume.
    #
    # Records are plain JSON-shaped hashes with string keys (the gem's own
    # stores round-trip through JSON, and Crew reads them back with string
    # keys), so they are stored verbatim rather than mapped onto columns.
    # run_id/parent_run_id/crew_name are mirrored into columns for querying.
    #
    # Unlike the gem's FileStore, an id needs no path sanitizing here -- it is
    # bound as a query parameter, never used to build a filesystem path.
    class ActiveRecordCheckpointStore
      def save(id, record)
        checkpoint = Checkpoint.find_or_initialize_by(run_id: id.to_s)
        checkpoint.data = record
        checkpoint.parent_run_id = record["parent_run_id"] || record[:parent_run_id]
        checkpoint.crew_name = record["crew"] || record[:crew]
        checkpoint.checkpoint_updated_at = parse_time(record["updated_at"] || record[:updated_at])
        checkpoint.save!
        record
      end

      def load(id)
        Checkpoint.find_by(run_id: id.to_s)&.data
      end

      def list
        Checkpoint.order(:id).pluck(:run_id)
      end

      def delete(id)
        Checkpoint.where(run_id: id.to_s).delete_all
        nil
      end

      private

      # The gem stamps an ISO8601 string. A malformed value must not take down
      # the run -- the column is a convenience mirror, the authoritative copy
      # lives in +data+.
      def parse_time(value)
        return nil if value.blank?

        Time.zone ? Time.zone.parse(value.to_s) : Time.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
