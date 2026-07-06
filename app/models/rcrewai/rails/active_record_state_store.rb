module RcrewAI
  module Rails
    # Persists rcrewai Flow state to the DB. Implements the core state-store
    # contract: save(id, hash) / load(id) => hash or nil. Pass an instance as
    # +state_store:+ when constructing a Flow.
    #
    # State is stored as JSON (see FlowState), so values must be JSON-native —
    # the same constraint as the core FileStateStore. A single flow run persists
    # from one process, so saves are effectively serial; a genuinely concurrent
    # first-write for the same state_id would hit the unique index and raise
    # ActiveRecord::RecordNotUnique (fail-loud, by design).
    class ActiveRecordStateStore
      def save(id, hash)
        record = FlowState.find_or_initialize_by(state_id: id)
        record.data = hash
        record.save!
      end

      def load(id)
        FlowState.find_by(state_id: id)&.data
      end
    end
  end
end
