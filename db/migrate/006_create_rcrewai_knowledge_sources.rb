class CreateRcrewaiKnowledgeSources < ActiveRecord::Migration[7.0]
  def change
    create_table :rcrewai_knowledge_sources do |t|
      t.references :owner, polymorphic: true, null: false
      t.string :source_type, null: false
      t.text :value, null: false
      t.boolean :active, default: true
      t.timestamps
    end
  end
end
