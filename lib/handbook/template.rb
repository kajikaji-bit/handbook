# frozen_string_literal: true
require "erb"
require "ripper"
module Handbook
  class Template
    def self.render(path:, assigns:)
      template = ERB.new(File.read(path))
      scope = Object.new
      assigns.each { |name, value| scope.instance_variable_set("@#{name}", value) }
      referenced = Ripper.lex(template.src).select { |token| token[1] == :on_ivar }.map { |token| token[2].to_sym }
      unless (referenced - scope.instance_variables).empty?
        raise GenerationError, "プロンプトに必要な変数がありません"
      end
      template.result(scope.instance_eval { binding })
    rescue GenerationError
      raise
    rescue StandardError, SyntaxError
      raise GenerationError, "テンプレートの展開に失敗しました"
    end
  end
end
