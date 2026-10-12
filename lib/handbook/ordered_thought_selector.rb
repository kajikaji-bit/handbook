# frozen_string_literal: true

module Handbook
  class OrderedThoughtSelector
    def call(thoughts:, conversation:, chosen:)
      (thoughts - chosen).first || thoughts.last
    end
  end
end
