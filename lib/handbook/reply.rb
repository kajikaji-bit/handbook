# frozen_string_literal: true

module Handbook
  class Reply
    attr_reader :kind, :text, :name, :arguments

    def self.message(text)
      new(kind: :message, text: text)
    end

    def self.finish(text)
      new(kind: :finish, text: text)
    end

    def self.tool_call(name:, arguments:)
      new(kind: :tool_call, name: name, arguments: arguments)
    end

    def initialize(kind:, text: nil, name: nil, arguments: nil)
      @kind = kind
      @text = text
      @name = name
      @arguments = arguments
    end
  end
end
