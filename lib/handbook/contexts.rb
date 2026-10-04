# frozen_string_literal: true

module Handbook
  class Contexts
    attr_reader :definitions

    def initialize
      @definitions = {}
    end

    def draw(&block)
      instance_eval(&block)
      self
    end

    def context(name, description:)
      @definitions[name] = { description: description }
    end
  end
end
