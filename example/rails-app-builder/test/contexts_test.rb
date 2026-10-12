# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../config/application"

class ContextsTest < Minitest::Test
  ORDER = %w[requirements system_requirements resource_design development runtime verification].freeze
  MODELS = [Requirement, SystemRequirement, ResourceDesign, VerificationItems].freeze

  class Client
    attr_reader :calls
    attr_accessor :choice
    def initialize; @calls = []; end
    def choose(**args)
      @calls << args
      completed = JSON.parse(args[:state]).fetch("completed_contexts")
      selected = choice || ORDER.find { |name| !completed.include?(name) }
      { "type" => "choice", "choice" => selected, "probabilities" => { selected => 1.0 }, "confidence" => 1.0 }
    end
  end

  class ThoughtScript
    def initialize(scripts)
      @scripts = scripts.transform_values(&:dup)
      @ordered = Handbook::OrderedThoughtSelector.new
    end
    def call(thoughts:, conversation:, chosen:)
      script = @scripts[conversation.name]
      return @ordered.call(thoughts: thoughts, conversation: conversation, chosen: chosen) unless script
      script.size > 1 ? script.shift : script.first
    end
  end

  class Generator
    RESULTS = {
      "requirement" => { statements: ["記事を投稿して、一覧と詳細で読めるブログが欲しい"] },
      "system_requirement" => { functions: ["記事を作成する", "記事を一覧する"], qualities: [], constraints: ["JSON で応答する"] },
      "resource_design" => { resources: [{ name: "Post", label: "記事", attributes: [{ name: "title", type: "string" }, { name: "body", type: "text" }], operations: %w[create index show] }], unresolved: [] },
      "verification_items" => { items: [{ name: "記事を作成できる", request: { method: "POST", path: "/posts", body: JSON.generate(post: { title: "初投稿" }) }, expect: { status: 201, body: JSON.generate(title: "初投稿") } }] }
    }.freeze
    attr_reader :calls
    def initialize; @calls = []; end
    def model; "fake"; end
    def generate(**args)
      @calls << args
      JSON.generate(RESULTS.fetch(args.fetch(:schema_name)))
    end
  end

  def setup
    @generator = Generator.new
    generator = @generator
    @originals = MODELS.to_h { |model| [model, model.method(:from)] }
    @originals.each do |model, original|
      model.define_singleton_method(:from) { |conversation, **| original.call(conversation, generator: generator) }
    end
    @client = Client.new
    @app = RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: @client))
  end

  def teardown
    @originals.each { |model, original| model.define_singleton_method(:from, original) }
  end

  def conversation(text, **options)
    Handbook::Conversation.new(id: "test", messages: [{ "role" => "user", "content" => text }], tools: [], **options)
  end

  def user_text
    <<~TEXT
      要求: 記事を投稿して、一覧と詳細で読めるブログが欲しい
      要件: 記事を作成して一覧できること。JSON で応答すること。
      リソース設計: Post に title と body を持たせ、作成・一覧・詳細ができること
    TEXT
  end

  def test_jev_receives_the_six_context_descriptions_in_order
    @app.call(conversation(user_text))
    criteria = @client.calls.first.fetch(:criteria)
    assert_equal ORDER, criteria.keys
    criteria.each_value { |description| refute_empty description }
  end

  def test_received_inputs_are_shown_and_then_the_build_command_is_executed
    input = conversation(user_text)
    replies = []
    reply = @app.call(input) { |r| replies << r }
    assert_nil reply
    assert_equal :tool_call, replies.last.kind
    assert_includes replies.last.arguments[:command], "/bin/build-app"
    shown = replies[0..-2].map(&:text).join("\n")
    assert_includes shown, "記事を投稿して、一覧と詳細で読めるブログが欲しい"
    assert_includes shown, "記事を作成する"
    assert_includes shown, "Post（記事）"
    assert_equal %w[requirements system_requirements resource_design], input.completed_contexts.map(&:to_s)
    assert_equal :development, input.context_name
    assert_equal "build", input.pending_tool["kind"]
    assert_equal %w[requirement system_requirement resource_design], @generator.calls.map { |c| c[:schema_name] }
  end

  def test_records_outside_act_are_wrapped_in_thought_tags
    input = conversation(user_text)
    @app.call(input) { |_| }
    input.histories.each_value do |entries|
      entries.reject { |e| e["thought"] == "act" }.each do |entry|
        assert_match(/\A<#{entry["thought"]}>.*<\/#{entry["thought"]}>\z/m, entry["text"])
      end
    end
    assert_includes input.context(:development).history.map { |e| e["text"] }, "<check>構築済みのアプリケーションが見当たらなかった</check>"
  end

  def test_successful_build_result_is_confirmed_and_startup_is_executed_next
    first = conversation(user_text)
    @app.call(first) { |_| }
    data = { "kind" => "build", "token" => first.pending_tool["token"], "app" => ApplicationBuild::OUTPUT, "success" => true }
    resumed = conversation(user_text, state: first.snapshot, context_name: :development, tool_result: { "content" => "HANDBOOK_RESULT=#{JSON.generate(data)}" })
    replies = []
    @app.call(resumed) { |r| replies << r }
    assert_includes resumed.context(:development).history.map { |e| e["text"] }, "<check>構築の成功を確認した</check>"
    assert_equal :tool_call, replies.last.kind
    assert_includes replies.last.arguments[:command], "/bin/start-app"
    assert_equal "run", resumed.pending_tool["kind"]
  end

  def test_failed_build_result_reports_that_the_request_was_not_met
    first = conversation(user_text)
    @app.call(first) { |_| }
    data = { "kind" => "build", "token" => first.pending_tool["token"], "app" => ApplicationBuild::OUTPUT, "success" => false, "error" => "rails new に失敗しました" }
    resumed = conversation(user_text, state: first.snapshot, context_name: :development, tool_result: { "content" => "HANDBOOK_RESULT=#{JSON.generate(data)}" })
    reply = @app.call(resumed)
    assert_equal :finish, reply.kind
    assert_includes resumed.context(:development).history.map { |e| e["text"] }, "<check>構築の失敗を確認した</check>"
    assert_nil resumed.pending_tool
  end

  def test_command_contexts_without_prerequisites_tell_the_user_and_finish
    { "development" => ["構築するリソース設計が足りない", "構築するリソース設計がありません。"],
      "runtime" => ["起動の前提の構築が足りない", "構築が完了していません。"],
      "verification" => ["検証の前提の起動が足りない", "起動が完了していません。"] }.each do |choice, (lack, text)|
      @client.choice = choice
      input = conversation(user_text)
      reply = @app.call(input)
      assert_equal :finish, reply.kind, choice
      assert reply.text.end_with?(text), reply.text
      assert_nil input.pending_tool
      history = input.context(choice).history.map { |e| e["text"] }
      assert_includes history, "<check>#{lack}</check>"
      refute history.any? { |t| t.start_with?("<plan>") }, choice
    end
  end

  def test_act_chosen_first_tells_the_missing_prerequisite_by_itself
    @client.choice = "development"
    app = RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: @client), thought_selector: ThoughtScript.new("development" => [:act]))
    input = conversation(user_text)

    reply = app.call(input)

    assert_equal :finish, reply.kind
    assert reply.text.end_with?("構築するリソース設計がありません。"), reply.text
    assert_equal %w[act], input.context(:development).history.map { |e| e["thought"] }
    assert_nil input.pending_tool
  end

  def test_build_result_is_confirmed_and_startup_follows_without_explain
    first = conversation(user_text)
    @app.call(first) { |_| }
    data = { "kind" => "build", "token" => first.pending_tool["token"], "app" => ApplicationBuild::OUTPUT, "success" => true }
    resumed = conversation(user_text, state: first.snapshot, context_name: :development, tool_result: { "content" => "HANDBOOK_RESULT=#{JSON.generate(data)}" })
    app = RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: @client), thought_selector: ThoughtScript.new("development" => [:check, :act], "runtime" => [:act]))
    replies = []

    app.call(resumed) { |r| replies << r }

    turn = resumed.context(:development).history.last(2)
    assert_equal %w[check act], turn.map { |e| e["thought"] }
    assert_equal "<check>構築の成功を確認した</check>", turn[0]["text"]
    assert_equal :tool_call, replies.last.kind
    assert_includes replies.last.arguments[:command], "/bin/start-app"
  end

  def test_inputs_are_shown_and_the_build_is_executed_when_only_act_is_chosen
    only_act = ORDER.to_h { |name| [name, [:act]] }
    app = RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: @client), thought_selector: ThoughtScript.new(only_act))
    input = conversation(user_text)
    replies = []

    app.call(input) { |r| replies << r }

    assert_equal :tool_call, replies.last.kind
    assert_includes replies.last.arguments[:command], "/bin/build-app"
    assert_includes replies[0..-2].map(&:text).join("\n"), "Post（記事）"
    assert input.histories.values.flatten.all? { |e| e["thought"] == "act" }
  end

  def test_unknown_choice_is_rejected_before_loading_controller
    @client.choice = "../../unknown"
    error = assert_raises(Handbook::JevError) { @app.call(conversation("test")) }
    assert_match(/未知/, error.message)
  end

  def test_empty_contexts_do_not_call_jev
    selector = Handbook::JevContextSelector.new(client: @client)
    assert_raises(ArgumentError) { selector.call(contexts: Handbook::Contexts.new, conversation: conversation("test")) }
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
  end

  def test_unreadable_requirement_is_safe_502
    def @generator.generate(**); JSON.generate(statements: []); end
    server = Handbook::Server.new(application: @app, model: "test")
    status, body = request(server, [{ role: "user", content: "ブログ" }])
    assert_equal 502, status
    refute_includes body, "statements"
  end

  def test_server_streams_the_shown_inputs_and_logs_the_selected_contexts
    log = StringIO.new
    server = Handbook::Server.new(application: @app, model: "test", logger: log)
    status, text = request(server, [{ role: "user", content: user_text }])
    assert_equal 200, status
    assert_includes text, "Post（記事）"
    selected = log.string.lines.map { |line| JSON.parse(line) }.select { |e| e["event"] == "context_selected" }
    assert_equal %w[requirements system_requirements resource_design development], selected.map { |e| e["context_name"] }
  end

  private

  def request(server, messages)
    env = Rack::MockRequest.env_for("/v1/chat/completions", method: "POST", input: JSON.generate(messages: messages, tools: [{ type: "function", function: { name: "bash" } }]))
    env["HTTP_X_SESSION_AFFINITY"] = "same-session"
    status, _, body = server.call(env)
    body = body.to_a
    return [status, body.join] unless status == 200
    [status, body.reject { |chunk| chunk.include?("[DONE]") }.map { |chunk| JSON.parse(chunk.delete_prefix("data: ")).dig("choices", 0, "delta", "content") }.compact.join]
  end
end
