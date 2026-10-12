require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "../lib/handbook"

class ThoughtSelectionTest < Minitest::Test
  class ScriptedSelector
    attr_reader :calls
    def initialize(*thoughts)
      @thoughts = thoughts
      @calls = []
    end
    def call(thoughts:, conversation:, chosen:)
      @calls << { thoughts: thoughts, context: conversation.name, chosen: chosen.dup }
      @thoughts.size > 1 ? @thoughts.shift : @thoughts.first
    end
  end

  class FakeJev
    attr_reader :calls
    def initialize(choice)
      @choice = choice
      @calls = []
    end
    def choose(**args)
      @calls << args
      { "type" => "choice", "choice" => @choice, "probabilities" => { @choice => 1.0 }, "confidence" => 1.0 }
    end
  end

  class DevelopmentController < Handbook::Controller
    def act = render(text: "構築を実行する", finish: true)
    def check = render(text: "構築済みのアプリケーションが見当たらなかった")
    def explain = render(text: "リソース設計を受け付けている")
    def plan = render(text: "構築を開始すると決めた")
  end

  def test_thoughts_lists_the_defined_thoughts_in_the_order_of_THOUGHTS
    klass = Class.new(Handbook::Controller) do
      def act = nil
      def check = nil
      def explain = nil
      private
      def build = nil
    end

    assert_equal %i[explain check act], klass.thoughts
    assert_equal %i[explain check act], Class.new(klass).thoughts
    assert_equal [], Handbook::Controller.thoughts
  end

  def test_process_calls_the_thoughts_in_the_order_the_selector_chooses
    { [:explain, :check, :act] => %w[explain check act],
      [:check, :act] => %w[check act],
      [:check, :plan, :check, :act] => %w[check plan check act] }.each do |script, expected|
      root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
      sent = []
      controller = DevelopmentController.new(conversation: root.context(:development), views_path: "/missing", thought_selector: ScriptedSelector.new(*script), responder: ->(r) { sent << r })

      assert_nil controller.process
      assert_equal expected, root.context(:development).history.map { |e| e["thought"] }
      assert_equal ["構築を実行する"], sent.map(&:text)
    end
  end

  def test_the_selector_receives_the_defined_thoughts_and_the_thoughts_chosen_so_far
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    selector = ScriptedSelector.new(:explain, :check, :act)

    DevelopmentController.new(conversation: root.context(:development), views_path: "/missing", thought_selector: selector, responder: ->(_) {}).process

    assert_equal [%i[explain check plan act]] * 3, selector.calls.map { |c| c[:thoughts] }
    assert_equal %w[development] * 3, selector.calls.map { |c| c[:context] }
    assert_equal [[], [:explain], [:explain, :check]], selector.calls.map { |c| c[:chosen] }
  end

  def test_finish_outside_act_ends_the_context_without_replying
    klass = Class.new(Handbook::Controller) do
      def check = render(text: "構築の成功を確認した", finish: true)
      def act = render(text: "構築を実行する")
    end
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    sent = []
    selector = ScriptedSelector.new(:check, :act)

    assert_nil klass.new(conversation: root.context(:development), views_path: "/missing", thought_selector: selector, responder: ->(r) { sent << r }).process

    assert_empty sent
    assert_equal [{"thought"=>"check", "text"=>"<check>構築の成功を確認した</check>"}], root.context(:development).history.map { |e| e.slice("thought", "text") }
    assert_equal 1, selector.calls.size
  end

  def test_an_act_that_replies_ends_the_context_after_the_act_returns
    klass = Class.new(Handbook::Controller) do
      def check = render(text: "検証の記録が見当たらなかった")
      def act
        render text: "検証項目"
        render text: "検証を実行する", finish: true
      end
    end
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    sent = []
    selector = ScriptedSelector.new(:act, :check)

    klass.new(conversation: root.context(:verification), views_path: "/missing", thought_selector: selector, responder: ->(r) { sent << r }).process

    assert_equal ["検証項目", "検証を実行する"], sent.map(&:text)
    assert_equal 1, selector.calls.size
  end

  def test_render_returns_true_so_that_and_return_leaves_the_thought
    klass = Class.new(Handbook::Controller) do
      def check
        render text: "構築するリソース設計が足りない" and return
        render text: "構築の成功を確認した"
      end
      def act
        render text: "構築するリソース設計がありません。", finish: true and return
        render text: "構築を実行する"
      end
    end
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    sent = []

    klass.new(conversation: root.context(:development), views_path: "/missing", thought_selector: ScriptedSelector.new(:check, :act), responder: ->(r) { sent << r }).process

    assert_equal ["<check>構築するリソース設計が足りない</check>", "構築するリソース設計がありません。"], root.context(:development).history.map { |e| e["text"] }
    assert_equal ["構築するリソース設計がありません。"], sent.map(&:text)
  end

  def test_process_stops_after_eight_selections_without_an_end
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    controller = DevelopmentController.new(conversation: root.context(:development), views_path: "/missing", thought_selector: ScriptedSelector.new(:check), responder: ->(_) {})

    error = assert_raises(Handbook::GenerationError) { controller.process }

    assert_equal "思考の選び直しが上限に達しました", error.message
    assert_equal 8, root.context(:development).history.size
  end

  def test_process_rejects_a_thought_the_controller_does_not_define
    klass = Class.new(Handbook::Controller) do
      def act = render(text: "構築を実行する", finish: true)
      private
      def build = nil
    end
    [:check, :build].each do |thought|
      root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
      controller = klass.new(conversation: root.context(:development), views_path: "/missing", thought_selector: ScriptedSelector.new(thought), responder: ->(_) {})

      error = assert_raises(Handbook::GenerationError) { controller.process }

      assert_equal "定義していない思考が選ばれました", error.message
      assert_empty root.context(:development).history
    end
  end

  def test_process_rejects_a_controller_without_thoughts_before_selecting
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    selector = ScriptedSelector.new(:act)

    error = assert_raises(Handbook::GenerationError) { Class.new(Handbook::Controller).new(conversation: root.context(:x), views_path: "/missing", thought_selector: selector).process }

    assert_equal "思考が定義されていません", error.message
    assert_empty selector.calls
  end

  def test_the_default_selector_calls_the_thoughts_in_the_order_of_THOUGHTS
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

    DevelopmentController.new(conversation: root.context(:development), views_path: "/missing", responder: ->(_) {}).process

    assert_equal %w[explain check plan act], root.context(:development).history.map { |e| e["thought"] }
  end

  def test_ordered_selector_chooses_the_first_thought_not_yet_chosen_and_then_keeps_the_last
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    selector = Handbook::OrderedThoughtSelector.new
    thoughts = %i[explain check act]

    assert_equal :explain, selector.call(thoughts: thoughts, conversation: root.context(:development), chosen: [])
    assert_equal :check, selector.call(thoughts: thoughts, conversation: root.context(:development), chosen: [:explain])
    assert_equal :act, selector.call(thoughts: thoughts, conversation: root.context(:development), chosen: [:explain, :check, :act])
  end

  def test_jev_selector_chooses_among_the_thoughts_by_their_fixed_descriptions
    jev = FakeJev.new("check")
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

    choice = Handbook::JevThoughtSelector.new(client: jev).call(thoughts: %i[explain check act], conversation: root.context(:development), chosen: [])

    assert_equal :check, choice
    assert_equal({ "explain" => "このコンテキストが受け取ったものと、会話と履歴からわかっていることを述べる", "check" => "前提がそろっているか、結果が出ているかを確かめ、足りないものを書き出す", "act" => "コマンドを実行するか、結果や足りないものを利用者へ伝えて、このコンテキストを終える" }, jev.calls.first[:criteria])
    assert_equal "このコンテキストで次に呼ぶ思考を一つ選ぶ。messages は会話とこのコンテキストの履歴で、act 以外の思考の記録は思考の名前のタグで囲まれている。chosen はこのターンですでに選んだ思考の並びで、選んでも記録が増えなかった思考は、いまはすることが無い。利用者へ伝えるかコマンドを実行してよいとわかったら act を選ぶ", jev.calls.first[:instructions]
  end

  def test_jev_selector_passes_the_context_messages_and_the_chosen_thoughts_as_state
    jev = FakeJev.new("act")
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    root.context(:development).record(:check, text: "<check>構築するリソース設計が足りない</check>")
    root.context(:runtime).record(:check, text: "<check>起動の前提の構築が足りない</check>")

    Handbook::JevThoughtSelector.new(client: jev).call(thoughts: %i[explain check act], conversation: root.context(:development), chosen: [:explain, :check])

    state = JSON.parse(jev.calls.first[:state])
    assert_equal ["依頼", "<check>構築するリソース設計が足りない</check>"], state["messages"].map { |m| m["content"] }
    assert_equal %w[explain check], state["chosen"]
  end

  def test_jev_selector_rejects_a_thought_outside_the_candidates
    jev = FakeJev.new("ask")
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

    error = assert_raises(Handbook::JevError) { Handbook::JevThoughtSelector.new(client: jev).call(thoughts: %i[explain check act], conversation: root.context(:development), chosen: []) }

    assert_equal "Jev が未知の思考を返しました", error.message
  end

  def test_application_selects_the_next_context_when_a_context_ends_without_replying
    Dir.mktmpdir do |root_path|
      controllers = File.join(root_path, "app/controllers")
      FileUtils.mkdir_p(controllers)
      File.write(File.join(controllers, "agent_controller.rb"), "")
      File.write(File.join(controllers, "intake_controller.rb"), <<~RUBY)
        class IntakeController < Handbook::Controller
          def check = render(text: "要求を受け付け済みと確認した", finish: true)
        end
      RUBY
      File.write(File.join(controllers, "summary_controller.rb"), <<~RUBY)
        class SummaryController < Handbook::Controller
          def act = render(text: "要件を受け付けた")
        end
      RUBY
      File.write(File.join(controllers, "answer_controller.rb"), <<~RUBY)
        class AnswerController < Handbook::Controller
          def act = render(text: "リソース設計を受け付けた", finish: true)
        end
      RUBY
      app_class = Class.new(Handbook::Application) { root root_path }
      app_class.contexts.draw do
        context :intake, description: "要求"
        context :summary, description: "要件"
        context :answer, description: "リソース設計"
      end
      selector = Object.new
      def selector.call(contexts:, conversation:)
        contexts.definitions.keys.find { |name| !conversation.completed_contexts.include?(name) }
      end
      thought_selector = ScriptedSelector.new(:check, :act, :act)
      conversation = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

      reply = app_class.new(selector: selector, thought_selector: thought_selector).call(conversation)

      assert_equal :finish, reply.kind
      assert_equal "要件を受け付けた\n\nリソース設計を受け付けた", reply.text
      assert_equal %i[intake summary], conversation.completed_contexts
      assert_equal %w[intake summary answer], thought_selector.calls.map { |c| c[:context] }
    ensure
      %i[IntakeController SummaryController AnswerController].each { |name| Object.send(:remove_const, name) if Object.const_defined?(name) }
    end
  end

  def test_application_stops_when_no_context_replies_within_the_iteration_limit
    Dir.mktmpdir do |root_path|
      controllers = File.join(root_path, "app/controllers")
      FileUtils.mkdir_p(controllers)
      File.write(File.join(controllers, "agent_controller.rb"), "")
      names = (1..8).map { |i| :"silent#{i}" }
      names.each do |name|
        File.write(File.join(controllers, "#{name}_controller.rb"), <<~RUBY)
          class #{name.to_s.capitalize}Controller < Handbook::Controller
            def check = render(text: "済んでいると確認した", finish: true)
          end
        RUBY
      end
      app_class = Class.new(Handbook::Application) { root root_path }
      app_class.contexts.draw { names.each { |name| context name, description: name.to_s } }
      selector = Object.new
      def selector.call(contexts:, conversation:)
        contexts.definitions.keys.find { |name| !conversation.completed_contexts.include?(name) }
      end
      conversation = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

      error = assert_raises(Handbook::GenerationError) { app_class.new(selector: selector).call(conversation) }

      assert_equal "コンテキストの反復上限に達しました", error.message
    ensure
      (1..8).map { |i| :"Silent#{i}Controller" }.each { |name| Object.send(:remove_const, name) if Object.const_defined?(name) }
    end
  end
end
