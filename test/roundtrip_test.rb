# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../lib/handbook"

class RoundtripTest < Minitest::Test
  def setup
    @seen = []
    application = lambda do |conversation|
      @seen << conversation
      if conversation.tool_result
        Handbook::Reply.finish("received: #{conversation.tool_result.fetch('content')}")
      elsif conversation.user_message == "run"
        conversation.context(:execution).record(:perceive, text: "prepared", data: {owner: conversation.id})
        Handbook::Reply.tool_call(name: "echo", arguments: { text: "test-output" })
      else
        Handbook::Reply.finish("hello")
      end
    end
    @log = StringIO.new
    @server = Handbook::Server.new(application: application, model: "test-model", logger: @log)
  end

  def test_fixed_reply_finishes_without_tool_calls
    chunks = send_messages("one", [{ "role" => "user", "content" => "hello" }])
    assert_equal "hello", chunks.first.dig("choices", 0, "delta", "content")
    assert_equal "stop", chunks.last.dig("choices", 0, "finish_reason")
    assert_nil chunks.first.dig("choices", 0, "delta", "tool_calls")
    assert_nil @seen.last.tool_result
  end

  def test_two_conversations_receive_their_own_tool_results
    starts = {}
    %w[one two].each do |id|
      history = [{ "role" => "user", "content" => "run" }]
      chunks = send_messages(id, history)
      assert_equal "tool_calls", chunks.last.dig("choices", 0, "finish_reason")
      call = chunks.first.dig("choices", 0, "delta", "tool_calls", 0).reject { |key, _| key == "index" }
      assert_equal "echo", call.dig("function", "name")
      assert_equal({ "text" => "test-output" }, JSON.parse(call.dig("function", "arguments")))
      starts[id] = [history, call]
    end
    refute_equal starts["one"][1]["id"], starts["two"][1]["id"]
    %w[two one].each do |id|
      history, call = starts.fetch(id)
      history += [
        { "role" => "assistant", "content" => nil, "tool_calls" => [call] },
        { "role" => "tool", "tool_call_id" => call["id"], "content" => "result-#{id}" }
      ]
      chunks = send_messages(id, history)
      assert_equal "received: result-#{id}", chunks.first.dig("choices", 0, "delta", "content")
      assert_equal "stop", chunks.last.dig("choices", 0, "finish_reason")
      assert_equal id, @seen.last.id
      assert_equal id, @seen.last.context(:execution).latest(:perceive)["owner"]
      assert_equal "prepared", @seen.last.context(:execution).perceptions.last["text"]
      assert_equal call["id"], @seen.last.tool_result["tool_call_id"]
      history += [{ "role" => "assistant", "content" => "done" }, { "role" => "user", "content" => "hello" }]
      send_messages(id, history)
      assert_nil @seen.last.tool_result
      assert_empty @seen.last.histories
    end
  end

  def test_text_parts_and_request_response_records
    send_messages("parts", [{ "role" => "user", "content" => [{ "type" => "text", "text" => "hello" }] }])
    assert_equal "hello", @seen.last.user_message
    events = @log.string.lines.map { |line| JSON.parse(line) }
    assert_equal %w[request response_chunk response_chunk response], events.map { |event| event["event"] }
    assert events.last["turn_finished"]
    assert_equal "parts", events.last["session_id"]
  end

  def test_unknown_tool_result_is_rejected_without_running_application
    env = Rack::MockRequest.env_for("/v1/chat/completions", method: "POST", input: JSON.generate(
      "messages" => [{"role"=>"tool", "tool_call_id"=>"unknown", "content"=>"success"}]
    ))
    env["HTTP_X_SESSION_AFFINITY"] = "unknown"
    status, _, response = @server.call(env)
    assert_equal 502, status
    assert_empty @seen
    refute_includes response.join, "stop"
  end

  private

  def send_messages(id, messages)
    body = {
      "model" => "test-model", "stream" => true, "messages" => messages,
      "tools" => [{ "type" => "function", "function" => {
        "name" => "echo", "parameters" => { "type" => "object", "properties" => { "text" => { "type" => "string" } } }
      } }]
    }
    env = Rack::MockRequest.env_for("/v1/chat/completions", method: "POST", input: JSON.generate(body))
    env["HTTP_X_SESSION_AFFINITY"] = id
    status, headers, response = @server.call(env)
    response = response.to_a
    assert_equal 200, status
    assert_equal "text/event-stream", headers["content-type"]
    assert_equal "data: [DONE]\n\n", response.last
    response[0...-1].map { |chunk| JSON.parse(chunk.delete_prefix("data: ").strip) }
  end
end
