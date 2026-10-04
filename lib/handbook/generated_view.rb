# frozen_string_literal: true

require "erb"
require "ripper"

module Handbook
  class GeneratedView
    attr_reader :prompt

    def initialize(path:, generator:)
      @path, @generator = path, generator
    end

    def render(assigns:)
      @prompt = Template.render(path: @path, assigns: assigns)
      @generator.generate(prompt: @prompt)
    rescue GenerationError
      raise
    rescue StandardError, SyntaxError
      raise GenerationError, "プロンプトの展開に失敗しました"
    end
  end
end
