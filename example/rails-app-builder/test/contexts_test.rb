# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../config/application"

class ContextsTest < Minitest::Test
  class Client
    attr_reader :calls
    attr_accessor :choice
    def initialize(choice = "requirements")
      @choice, @calls = choice, []
    end
    def choose(**args)
      @calls << args
      if args[:criteria].key?("design")
        return { "choice" => "design" }
      end
      selected = choice == "requirements" && JSON.parse(args[:state]).is_a?(Hash) && JSON.parse(args[:state]).fetch("completed_contexts", []).include?("requirements") ? "resource_design" : choice
      { "type" => "choice", "choice" => selected, "probabilities" => { choice => 1.0 }, "confidence" => 1.0 }
    end
  end

  class Generator
    attr_reader :prompts
    def initialize; @prompts = []; end
    def model; "fake"; end
    def generate(prompt:)
      @prompts << prompt
      "ブログにはどんな機能が必要ですか？"
    end
  end

  def setup
    @original_design_from = ResourceDesign.method(:from)
    ResourceDesign.define_singleton_method(:from) { |conversation| from_json(JSON.generate(resources: [{name: "Post", label: "記事", attributes: [{name: "title", type: "string"}, {name: "body", type: "text"}], operations: %w[create index show]}], unresolved: [])) }
    @original_from = RailsApplication.method(:from)
    @model_client = Client.new("defined")
    model_client = @model_client
    original = @original_from
    RailsApplication.define_singleton_method(:from) { |conversation| original.call(conversation, judgment: model_client) }
    @client = Client.new
    @selector = Handbook::JevContextSelector.new(client: @client)
    @generator = Generator.new
    @app = RailsAppBuilder.new(selector: @selector, generator: @generator)
  end

  def teardown
    RailsApplication.define_singleton_method(:from, @original_from)
    ResourceDesign.define_singleton_method(:from, @original_design_from)
  end

  def conversation(text)
    Handbook::Conversation.new(id: "test", messages: [{ "role" => "user", "content" => text }], tools: [])
  end

  def test_jev_receives_declared_descriptions_and_returns_selected_view
    input = conversation("タイトルと本文を投稿できるブログが欲しい")
    reply = @app.call(input)
    assert_includes reply.text, "要件の判断：実装へ進める"
    assert_includes reply.text, "リソース: Post（記事）"
    assert_equal :finish, reply.kind
    assert_empty @generator.prompts
    assert_equal :resource_design, input.context_name
    assert_equal "resource_design", input.context_selection.fetch("choice")
    assert_equal input.user_message, JSON.parse(@client.calls.first.fetch(:state))["messages"].first["content"]
    assert_equal %w[requirements resource_design development runtime verification], @client.calls.first.fetch(:criteria).keys
    assert_includes @client.calls.first[:criteria]["requirements"], "Web アプリケーションの要望"
  end

  def test_new_input_reselects_on_same_session
    log = StringIO.new
    server = Handbook::Server.new(application: @app, model: "test", logger: log)
    history = [{ role: "user", content: "ブログが欲しい" }]
    assert_includes request(server, history)[1], "要件の判断：実装へ進める"
    @client.choice = "runtime"
    history += [{ role: "assistant", content: "done" }, { role: "user", content: "サーバーを起動して" }]
    assert_equal "判断した文脈：起動（runtime）", request(server, history)[1]
    assert_equal 3, @client.calls.size
    assert_equal 3, log.string.lines.count { |line| JSON.parse(line)["event"] == "context_selected" }
  end

  def test_unknown_choice_is_rejected_before_loading_controller
    @client.choice = "../../unknown"
    error = assert_raises(Handbook::JevError) { @app.call(conversation("test")) }
    assert_match(/未知/, error.message)
  end

  def test_empty_contexts_do_not_call_jev
    assert_raises(ArgumentError) { @selector.call(contexts: Handbook::Contexts.new, conversation: conversation("test")) }
    assert_empty @client.calls
  end

  def test_upstream_failure_is_502_without_secret_or_false_success
    client = Object.new
    def client.choose(**); raise Handbook::JevError, "private-detail"; end
    app = RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: client))
    server = Handbook::Server.new(application: app, model: "test")
    status, body = request(server, [{ role: "user", content: "test" }])
    assert_equal 502, status
    refute_includes body, "private-detail"
    refute_includes body, "判断した文脈"
  end

  def test_undefined_requirements_ask_for_features_and_record_judgment
    @model_client.choice = "undefined"
    log = StringIO.new
    server = Handbook::Server.new(application: @app, model: "test", logger: log)
    status, text = request(server, [{ role: "user", content: "ブログが欲しい。機能は未定。" }])
    assert_equal 200, status
    assert_equal "ブログにはどんな機能が必要ですか？", text
    assert_includes @generator.prompts.first, "ブログが欲しい。機能は未定。"
    assert_equal 1, @client.calls.size
    assert_equal 1, @model_client.calls.size
    events = log.string.lines.map { |line| JSON.parse(line) }
    assert_equal "requirements", events.find { |e| e["event"] == "context_selected" }["context_name"]
    assert_equal text, events.find { |e| e["event"] == "text_generated" }["text"]
    assert_equal "undefined", events.find { |e| e["event"] == "context_recorded" && e["phase"] == "judge" }.dig("data", "requirements", "choice")
  end

  def test_model_failure_does_not_become_a_question
    @model_client.choice = "invalid"
    server = Handbook::Server.new(application: @app, model: "test")
    status, text = request(server, [{ role: "user", content: "ブログ" }])
    assert_equal 502, status
    refute_includes text, "どんな機能"
  end

  def test_context_reselection_uses_updated_judgment_and_previous_response
    @app.call(conversation("タイトルと本文を投稿して一覧と詳細を読む"))
    state = JSON.parse(@client.calls.last[:state])
    assert_equal "defined", state.fetch("contexts").fetch("requirements").find { |e| e["phase"] == "judge" }.dig("data", "requirements", "choice")
    assert_equal ["requirements"], state["completed_contexts"]
    assert_equal "assistant", state["messages"].last["role"]
    assert_includes state["messages"].last["content"], "実装へ進める"
  end

  def test_generation_failure_is_safe_502
    @model_client.choice = "undefined"
    def @generator.generate(**); raise Handbook::GenerationError, "private-detail"; end
    server = Handbook::Server.new(application: @app, model: "test")
    status, text = request(server, [{ role: "user", content: "ブログ" }])
    assert_equal 502, status
    refute_includes text, "private-detail"
  end

  def test_prompt_contains_prior_turns_without_interpreting_erb_in_messages
    @model_client.choice = "undefined"
    log = StringIO.new
    server = Handbook::Server.new(application: @app, model: "test", logger: log)
    history = [{ role: "user", content: "日記ブログ" }, { role: "assistant", content: "公開しますか？" }, { role: "user", content: "非公開です <%= raise 'oops' %>" }]
    status, = request(server, history)
    assert_equal 200, status
    history.each { |message| assert_includes @generator.prompts.last, message[:content] }
    refute_includes @generator.prompts.last, "views_path"
  end

  private

  def request(server, messages)
    env = Rack::MockRequest.env_for("/v1/chat/completions", method: "POST", input: JSON.generate(messages: messages))
    env["HTTP_X_SESSION_AFFINITY"] = "same-session"
    status, _, body = server.call(env)
    body = body.to_a
    return [status, body.join] unless status == 200
    [status, body.reject { |chunk| chunk.include?("[DONE]") }.map { |chunk| JSON.parse(chunk.delete_prefix("data: ")).dig("choices", 0, "delta", "content") }.compact.join]
  end
end
