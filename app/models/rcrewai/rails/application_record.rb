module RcrewAI
  module Rails
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
      self.table_name_prefix = "rcrewai_"
    end
  end
end