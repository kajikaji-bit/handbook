# frozen_string_literal: true

module Handbook
  class Application
    def self.root(path = nil)
      @root = path if path
      @root
    end

    def self.contexts
      @contexts ||= Contexts.new
    end

    def initialize(selector: StringMatcher.new, generator: nil)
      @selector = selector
      @generator = generator
    end

    def call(conversation, &sink)
      collected = []
      sink ||= ->(reply) { collected << reply }
      terminal = false
      8.times do
        name = conversation.context_name || @selector.call(contexts: self.class.contexts, conversation: conversation)
        conversation.context_name = name
        if conversation.context_selection
          conversation.events.call("context_selected", context_name: name, selection: conversation.context_selection, input: conversation.selection_state)
        end
        root = self.class.root
        require File.join(root, "app/controllers/agent_controller")
        require File.join(root, "app/controllers", "#{name}_controller")
        class_name = name.to_s.split("_").map(&:capitalize).join + "Controller"
        emitted = false
        responder = lambda do |reply|
          raise GenerationError, "終了後に応答できません" if terminal
          emitted = true
          terminal = reply.kind != :message
          sink.call(reply)
          conversation.messages << { "role" => "assistant", "content" => reply.text } if reply.text
        end
        Object.const_get(class_name).new(conversation: conversation.context(name), views_path: File.join(root, "app/views", name.to_s), generator: @generator, responder: responder).process
        raise GenerationError, "コントローラが応答しませんでした" unless emitted
        if terminal
          return nil if collected.empty?
          return collected.last if collected.last.kind == :tool_call
          return Reply.finish(collected.map(&:text).compact.join("\n\n"))
        end
        if conversation.completed_contexts.include?(name)
          raise GenerationError, "コンテキストの処理が進みません"
        end
        conversation.completed_contexts << name
        conversation.context_name = nil
        conversation.context_selection = nil
      end
      raise GenerationError, "コンテキストの反復上限に達しました"
    end
  end
end
