# frozen_string_literal: true

module Handbook
  class Controller
    attr_reader :conversation

    THOUGHTS = %i[explain ask check plan act].freeze
    SELECTION_LIMIT = 8

    def self.thoughts
      THOUGHTS.select { |thought| public_method_defined?(thought) }
    end

    def initialize(conversation:, views_path:, generator: nil, thought_selector: OrderedThoughtSelector.new, responder: nil)
      @conversation = conversation
      @views_path = views_path
      @generator = generator
      @thought_selector = thought_selector
      @responder = responder
      @execution = { thought: :act, finished: false }
      @internal_variables = instance_variables + [:@internal_variables]
      @internal_values = @internal_variables.to_h { |name| [name, instance_variable_get(name)] }
      @internal_variables << :@internal_values
    end

    def process
      thoughts = self.class.thoughts
      raise GenerationError, "思考が定義されていません" if thoughts.empty?
      chosen = []
      SELECTION_LIMIT.times do
        thought = @thought_selector.call(thoughts: thoughts, conversation: conversation, chosen: chosen.dup)
        raise GenerationError, "定義していない思考が選ばれました" unless thoughts.include?(thought)
        chosen << thought
        think(thought)
        return nil if @execution[:finished]
      end
      raise GenerationError, "思考の選び直しが上限に達しました"
    end

    private

    def render(view = nil, tool: nil, generate: false, finish: false, json: nil, text: nil)
      raise GenerationError, "act 以外の思考からツールは実行できません" if tool && !acting?
      if json || text
        raise GenerationError, "ビューと直接の内容を同時には指定できません" if view || tool || generate || (json && text)
        content = json ? JSON.generate(json) : text
        return send_reply(finish ? Reply.finish(content) : Reply.message(content), data: json)
      end
      raise GenerationError, "ツールと終了指定は同時に使えません" if tool && finish
      if generate
        raise GenerationError, "生成とツール指定は同時に使えません" if tool
        unless @internal_values.all? { |name, value| instance_variable_get(name).equal?(value) }
          raise GenerationError, "ビュー用の変数が内部変数と衝突しています"
        end
        assigns = view_assigns
        generator = @generator || OpenRouterClient.new
        generated = GeneratedView.new(path: File.join(@views_path, "#{view}.prompt.erb"), generator: generator)
        text = generated.render(assigns: assigns)
        conversation.events.call("text_generated", view: view, prompt: generated.prompt, text: text, model: generator.model)
        return send_reply(finish ? Reply.finish(text) : Reply.message(text))
      end
      extension = tool ? "sh" : "txt"
      path = File.join(@views_path, "#{view}.#{extension}")
      content = if File.exist?(path + ".erb")
        Template.render(path: path + ".erb", assigns: view_assigns).strip
      else
        File.read(path).chomp
      end
      if tool
        send_reply(Reply.tool_call(name: tool.to_s, arguments: { command: content }))
      else
        send_reply(finish ? Reply.finish(content) : Reply.message(content))
      end
    end

    def view_assigns
      unless @internal_values.all? { |name, value| instance_variable_get(name).equal?(value) }
        raise GenerationError, "ビュー用の変数が内部変数と衝突しています"
      end
      (instance_variables - @internal_variables).to_h { |name| [name.to_s.delete_prefix("@").to_sym, instance_variable_get(name)] }
    end

    def think(thought)
      @execution[:thought] = thought
      public_send(thought)
    end

    def acting?
      @execution[:thought] == :act
    end

    def send_reply(reply, data: nil)
      if conversation.respond_to?(:record)
        conversation.record(@execution[:thought], text: recorded_text(reply), data: data)
      end
      @execution[:finished] = true if acting? || reply.kind == :finish
      @responder&.call(reply) if acting?
      true
    end

    def recorded_text(reply)
      text = reply.text || JSON.generate(reply.arguments)
      return text if acting?
      "<#{@execution[:thought]}>#{text}</#{@execution[:thought]}>"
    end
  end
end
