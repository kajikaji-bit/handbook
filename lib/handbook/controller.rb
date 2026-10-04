# frozen_string_literal: true

module Handbook
  class Controller
    attr_reader :conversation

    def initialize(conversation:, views_path:, generator: nil, responder: nil)
      @conversation = conversation
      @views_path = views_path
      @generator = generator
      @responder = responder
      @execution = { phase: :act }
      @internal_variables = instance_variables + [:@internal_variables]
      @internal_values = @internal_variables.to_h { |name| [name, instance_variable_get(name)] }
      @internal_variables << :@internal_values
    end

    def process
      [:perceive, :judge, :act].each do |phase|
        @execution[:phase] = phase
        public_send(phase)
      end
    end

    def perceive; end
    def judge; end

    private

    def render(view = nil, tool: nil, generate: false, finish: false, json: nil, text: nil)
      if @execution[:phase] != :act && (tool || finish)
        raise GenerationError, "知覚と判断からツール実行やターン終了はできません"
      end
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

    def send_reply(reply, data: nil)
      if conversation.respond_to?(:record)
        conversation.record(@execution[:phase], text: reply.text || JSON.generate(reply.arguments), data: data)
      end
      return nil unless @execution[:phase] == :act
      return reply unless @responder
      @responder.call(reply)
      nil
    end
  end
end
