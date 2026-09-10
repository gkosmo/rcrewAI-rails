require "rails_helper"

RSpec.describe RcrewAI::Rails::ActiveRecordCheckpointStore, type: :model do
  let(:store) { described_class.new }

  def record(run_id: "run-1", parent: nil, tasks: {})
    RCrewAI::Checkpoint.record_for(
      run_id: run_id, crew_name: "demo", tasks: tasks, parent_run_id: parent
    )
  end

  describe "the store contract" do
    it "round-trips a record by id" do
      store.save("run-1", record(tasks: { "t" => { "status" => "completed" } }))

      loaded = store.load("run-1")
      expect(loaded["run_id"]).to eq("run-1")
      expect(loaded["crew"]).to eq("demo")
      expect(loaded["tasks"]).to eq({ "t" => { "status" => "completed" } })
    end

    it "updates rather than duplicating on repeat save" do
      store.save("run-1", record)
      store.save("run-1", record(tasks: { "t" => { "status" => "failed" } }))

      expect(RcrewAI::Rails::Checkpoint.where(run_id: "run-1").count).to eq(1)
      expect(store.load("run-1")["tasks"]).to eq({ "t" => { "status" => "failed" } })
    end

    it "returns nil for an unknown id" do
      expect(store.load("missing")).to be_nil
    end

    it "lists saved run ids" do
      store.save("run-1", record(run_id: "run-1"))
      store.save("run-2", record(run_id: "run-2"))

      expect(store.list).to contain_exactly("run-1", "run-2")
    end

    it "deletes a run and is a no-op for an unknown id" do
      store.save("run-1", record)

      expect(store.delete("run-1")).to be_nil
      expect(store.load("run-1")).to be_nil
      expect { store.delete("missing") }.not_to raise_error
    end

    # The gem's FileStore rejects these to avoid path traversal. Nothing here
    # builds a path, so they are ordinary ids and must not raise.
    it "accepts ids that the file-backed store would reject" do
      store.save("../escape", record(run_id: "../escape"))
      expect(store.load("../escape")["run_id"]).to eq("../escape")
    end
  end

  describe "column mirroring" do
    it "mirrors parent, crew and updated_at onto columns" do
      store.save("run-2", record(run_id: "run-2", parent: "run-1"))

      checkpoint = RcrewAI::Rails::Checkpoint.find_by(run_id: "run-2")
      expect(checkpoint.parent_run_id).to eq("run-1")
      expect(checkpoint.crew_name).to eq("demo")
      expect(checkpoint.checkpoint_updated_at).to be_present
    end

    it "keeps a run with an unparseable timestamp rather than failing the save" do
      malformed = record.merge("updated_at" => "not-a-time")

      expect { store.save("run-1", malformed) }.not_to raise_error
      expect(store.load("run-1")).to be_present
      expect(RcrewAI::Rails::Checkpoint.find_by(run_id: "run-1").checkpoint_updated_at).to be_nil
    end
  end

  describe "lineage" do
    it "walks a resumed chain back to the root via the gem's own helper" do
      store.save("run-1", record(run_id: "run-1"))
      store.save("run-2", record(run_id: "run-2", parent: "run-1"))
      store.save("run-3", record(run_id: "run-3", parent: "run-2"))

      expect(RCrewAI::Checkpoint.lineage(store, "run-3")).to eq(%w[run-1 run-2 run-3])
    end

    it "exposes children and task status helpers" do
      store.save("run-1", record(run_id: "run-1", tasks: {
                                   "done" => { "status" => "completed" },
                                   "broke" => { "status" => "failed" }
                                 }))
      store.save("run-2", record(run_id: "run-2", parent: "run-1"))

      root = RcrewAI::Rails::Checkpoint.find_by(run_id: "run-1")
      expect(root.completed_task_names).to eq(["done"])
      expect(root.failed_task_names).to eq(["broke"])
      expect(root.children.pluck(:run_id)).to eq(["run-2"])
      expect(RcrewAI::Rails::Checkpoint.roots.pluck(:run_id)).to eq(["run-1"])
    end
  end
end
