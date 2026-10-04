# frozen_string_literal: true

module Handbook
  class Conversation
    attr_reader :id, :messages, :tools, :tool_result, :completed_contexts, :histories
    attr_accessor :context_name, :context_selection, :events, :pending_tool

    def initialize(id:, messages:, tools:, tool_result: nil, context_name: nil, state: nil)
      @events = ->(*) {}
      @histories = state ? state.fetch(:histories) : {}
      @completed_contexts = state ? state.fetch(:completed_contexts) : []
      @pending_tool = state && state[:pending_tool]
      @id, @tools, @tool_result, @context_name = id, tools, tool_result, context_name
      @messages = messages.map(&:dup)
    end

    def context(name)
      ContextConversation.new(self, name.to_s)
    end

    def snapshot
      Marshal.load(Marshal.dump({ histories: histories, completed_contexts: completed_contexts, pending_tool: pending_tool }))
    end

    def selection_state
      { messages: messages, contexts: histories, completed_contexts: completed_contexts }
    end

    def user_message
      content = messages.reverse.find { |message| message["role"] == "user" }.fetch("content")
      return content if content.is_a?(String)
      content.select { |part| part["type"] == "text" }.map { |part| part["text"] }.join("\n")
    end
  end

  class ContextConversation
    attr_reader :name

    def initialize(conversation, name)
      @conversation, @name = conversation, name
    end

    def history
      Marshal.load(Marshal.dump(@conversation.histories.fetch(name, [])))
    end

    def messages
      @conversation.messages + history.map { |entry| { "role" => "assistant", "content" => entry.fetch("text"), "context" => name, "phase" => entry.fetch("phase") } }
    end

    def perceptions; history.select { |entry| entry["phase"] == "perceive" }; end
    def judgments; history.select { |entry| entry["phase"] == "judge" }; end
    def latest(phase); history.reverse.find { |entry| entry["phase"] == phase.to_s }&.fetch("data"); end

    def record(phase, text:, data: nil)
      raise ArgumentError, "未知の段階です" unless %w[perceive judge act].include?(phase.to_s)
      entry = JSON.parse(JSON.generate(context: name, phase: phase.to_s, text: text, data: data))
      (@conversation.histories[name] ||= []) << entry
      events.call("context_recorded", **entry.transform_keys(&:to_sym))
      nil
    end

    def context(name); @conversation.context(name); end
    def user_message; @conversation.user_message; end
    def tool_result; @conversation.tool_result; end
    def events; @conversation.events; end
    def pending_tool; @conversation.pending_tool; end
    def pending_tool=(value); @conversation.pending_tool = value; end
  end
end
