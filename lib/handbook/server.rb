# frozen_string_literal: true

module Handbook
  class Server
    def initialize(application:, model:, logger: nil)
      @application = application
      @model = model
      @logger = logger
      @sessions = {}
      @mutex = Mutex.new
    end

    class Stream
      include Enumerable
      def initialize(&producer)
        @fiber = Fiber.new { producer.call(->(chunk) { Fiber.yield(chunk) }); nil }
        @first = @fiber.resume
      end

      def each
        return enum_for(:each) unless block_given?
        begin
          yield @first if @first
          @first = nil
          while @fiber.alive?
            chunk = @fiber.resume
            yield chunk if chunk
          end
        ensure
          close
        end
      end

      def close
        @fiber.raise(IOError, "stream closed") if @fiber.alive?
      rescue IOError
        nil
      end
    end

    def call(env)
      request = JSON.parse(env.fetch("rack.input").read)
      session_id = env.fetch("HTTP_X_SESSION_AFFINITY")
      stream = Stream.new do |emit|
        @mutex.synchronize { respond(session_id, request, emit) }
      end
      [200, { "content-type" => "text/event-stream", "cache-control" => "no-cache" }, stream]
    rescue GenerationError, JevError
      [502, { "content-type" => "application/json" }, [JSON.generate(error: {
        message: "判断または生成に失敗しました。", type: "upstream_error"
      })]]
    end

    private

    def respond(session_id, request, emit)
      session = (@sessions[session_id] ||= { pending: {} })
      messages = request.fetch("messages")
      tools = request.fetch("tools", [])
      record("request", session_id, body: request)
      result, context_name, state = receive_result(session, messages)
      conversation = Conversation.new(id: session_id, messages: messages, tools: tools, tool_result: result, context_name: context_name, state: state)
      conversation.events = ->(event, **data) { record(event, session_id, **data) }
      base = {
        "id" => "chatcmpl-#{SecureRandom.hex(12)}", "object" => "chat.completion.chunk",
        "created" => Time.now.to_i, "model" => @model
      }
      chunks = []
      emitted = false
      terminal = false
      send_chunk = lambda do |delta, reason|
        chunk = base.merge("choices" => [{ "index" => 0, "delta" => delta, "finish_reason" => reason }])
        chunks << chunk
        record("response_chunk", session_id, chunk: chunk)
        emitted = true
        emit.call("data: #{JSON.generate(chunk)}\n\n")
      end
      responder = lambda do |reply|
        raise GenerationError, "終了後に応答できません" if terminal
        delta, reason = render_reply(session, reply, tools, conversation.context_name, conversation.snapshot)
        delta["content"] = "\n\n" + delta["content"] if emitted && delta["content"]
        send_chunk.call(delta, nil)
        if reason
          terminal = true
          send_chunk.call({}, reason)
          record("response", session_id, chunks: chunks, turn_finished: reason == "stop")
        end
      end
      reply = @application.call(conversation, &responder)
      responder.call(reply) if !emitted && reply.is_a?(Reply)
      raise GenerationError, "終了応答がありません" unless terminal
      emit.call("data: [DONE]\n\n")
    rescue GenerationError, JevError => error
      record("response_error", session_id, error_class: error.class.name, turn_finished: false)
      raise unless emitted
      emit.call("data: #{JSON.generate(error: { message: "判断または生成に失敗しました。", type: "upstream_error" })}\n\n")
      emit.call("data: [DONE]\n\n")
    end

    def receive_result(session, messages)
      result = messages.last
      return unless result["role"] == "tool"

      id = result.fetch("tool_call_id")
      pending = session[:pending].fetch(id) { raise GenerationError, "対応するツール要求がありません" }
      request = pending.fetch(:call)
      session[:pending].delete(id)
      [result.merge("name" => request.fetch("function").fetch("name")), pending[:context_name], pending[:state]]
    end

    def render_reply(session, reply, tools, context_name, state)
      if [:message, :finish].include?(reply.kind)
        [{ "role" => "assistant", "content" => reply.text }, reply.kind == :finish ? "stop" : nil]
      else
        definition = tools.find { |tool| tool.dig("function", "name") == reply.name }
        name = definition.fetch("function").fetch("name")
        id = "call_#{SecureRandom.hex(12)}"
        call = {
          "id" => id, "type" => "function",
          "function" => { "name" => name, "arguments" => JSON.generate(reply.arguments) }
        }
        session[:pending][id] = { call: call, context_name: context_name, state: state }
        [{ "role" => "assistant", "tool_calls" => [call.merge("index" => 0)] }, "tool_calls"]
      end
    end

    def record(event, session_id, **details)
      @logger&.puts(JSON.generate({ time: Time.now.utc.iso8601(6), event: event, session_id: session_id }.merge(details)))
    end
  end
end
