module RcrewAI
  module Rails
    # One persisted rcrewai checkpoint run record.
    #
    # The gem writes a plain JSON-shaped hash per run (see
    # RCrewAI::Checkpoint.record_for); +data+ holds it verbatim so a record
    # written by any store implementation round-trips identically. run_id and
    # parent_run_id are also mirrored into columns so lineage can be queried in
    # SQL rather than by deserializing every row.
    class Checkpoint < ApplicationRecord
      self.table_name = "rcrewai_checkpoints"

      serialize :data, coder: JSON

      validates :run_id, presence: true, uniqueness: true

      scope :roots, -> { where(parent_run_id: nil) }

      def children
        self.class.where(parent_run_id: run_id)
      end

      # The per-task entries of the stored record, keyed by task name.
      def tasks
        (data || {})["tasks"] || {}
      end

      def completed_task_names
        tasks.select { |_name, entry| entry["status"] == "completed" }.keys
      end

      def failed_task_names
        tasks.select { |_name, entry| entry["status"] == "failed" }.keys
      end
    end
  end
end
