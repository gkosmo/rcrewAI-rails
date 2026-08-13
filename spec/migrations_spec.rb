require "rails_helper"

# Rails resolves a migration's class from its filename via the active
# inflections. This engine registers an `RcrewAI` acronym (which Zeitwerk needs
# to map rcrewai/rails/span.rb -> RcrewAI::Rails::Span), so any migration named
# *_rcrewai_* camelizes to `RcrewAI`, not `Rcrewai`.
#
# 0.7.0 shipped 9 migrations plus the install template whose class names
# disagreed with that, so `rails db:migrate` raised NameError on a verbatim
# install. These are the migrations host apps run, so a mismatch is only
# reachable in someone else's app — hence this spec.
RSpec.describe "migration class names" do
  def declared_class_name(path)
    File.read(path)[/class (\w+)/, 1]
  end

  def expected_class_name(path)
    ActiveSupport::Inflector.camelize(
      File.basename(path, ".rb").sub(/\A\d+_/, "")
    )
  end

  engine_root = File.expand_path("..", __dir__)
  migrations = Dir[File.join(engine_root, "db/migrate/*.rb")].sort
  template = File.join(
    engine_root,
    "lib/generators/rcrewai/rails/install/templates/create_rcrewai_tables.rb"
  )

  it "finds migrations to check" do
    expect(migrations).not_to be_empty
  end

  (migrations + [template]).each do |path|
    it "#{File.basename(path)} declares the class Rails derives from its filename" do
      expect(declared_class_name(path)).to eq(expected_class_name(path)),
                                           "Rails will look for #{expected_class_name(path)} but the file " \
                                           "declares #{declared_class_name(path)}; `rails db:migrate` raises NameError"
    end
  end
end
