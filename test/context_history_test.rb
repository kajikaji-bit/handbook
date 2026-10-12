require "minitest/autorun"
require "tmpdir"
require_relative "../lib/handbook"

class ContextHistoryTest < Minitest::Test
  class Controller < Handbook::Controller
    def explain
      @topic = conversation.user_message
      render :explanation
    end
    def ask
      render text: "足りない情報は無い"
    end
    def check
      render json: {ready: true}
    end
    def plan
      render text: "利用者へ伝えると決めた"
    end
    def act
      render text: "利用者への表示", finish: true
    end
  end

  def test_process_records_each_chosen_thought_and_replies_only_from_act
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    root.context(:other).record(:check, text: "別の確認", data: {ready: false})
    sent = []
    Dir.mktmpdir do |path|
      File.write(File.join(path, "explanation.txt.erb"), "読み取った要求: <%= @topic %>")
      Controller.new(conversation: root.context(:requirements), views_path: path, responder: ->(r) { sent << r }).process
    end
    assert_equal ["利用者への表示"], sent.map(&:text)
    assert_equal [:finish], sent.map(&:kind)
    scoped = root.context(:requirements)
    assert_equal %w[explain ask check plan act], scoped.history.map { |e| e["thought"] }
    refute_includes scoped.messages.map { |e| e["content"] }, "<check>{\"ready\":false}</check>"
    assert_equal ["依頼"], root.messages.map { |e| e["content"] }
    assert root.selection_state[:contexts].key?("other")
  end

  def test_render_outside_act_wraps_the_record_in_a_tag_named_after_the_thought
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    Dir.mktmpdir do |path|
      File.write(File.join(path, "explanation.txt.erb"), "読み取った要求: <%= @topic %>")
      Controller.new(conversation: root.context(:requirements), views_path: path, responder: ->(_) {}).process
    end
    texts = root.context(:requirements).history.map { |e| e["text"] }
    assert_equal "<explain>読み取った要求: 依頼</explain>", texts[0]
    assert_equal "<ask>足りない情報は無い</ask>", texts[1]
    assert_equal "<check>{\"ready\":true}</check>", texts[2]
    assert_equal "<plan>利用者へ伝えると決めた</plan>", texts[3]
    assert_equal "利用者への表示", texts[4]
  end

  def test_render_json_before_act_keeps_the_data_for_latest
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    Dir.mktmpdir do |path|
      File.write(File.join(path, "explanation.txt.erb"), "読み取った要求: <%= @topic %>")
      Controller.new(conversation: root.context(:requirements), views_path: path, responder: ->(_) {}).process
    end
    assert_equal true, root.context(:requirements).latest(:check)["ready"]
    assert_nil root.context(:runtime).latest(:check)
  end

  def test_record_rejects_unknown_thoughts
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    assert_raises(ArgumentError) { root.context(:development).record(:perceive, text: "結果") }
    assert_raises(ArgumentError) { root.context(:development).record(:judge, text: "判断") }
    assert_empty root.histories
  end

  def test_snapshot_restores_histories_without_sharing_mutable_values
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    root.context(:requirements).record(:check, text: "<check>定義済み</check>", data: {ready: true})
    root.pending_tool = {"kind"=>"build", "token"=>"token"}
    snapshot = root.snapshot
    root.context(:requirements).record(:check, text: "<check>後の確認</check>")
    restored = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [], state: snapshot)
    assert_equal 1, restored.context(:requirements).history.size
    assert_equal true, restored.context(:requirements).latest(:check)["ready"]
    assert_equal "token", restored.pending_tool["token"]
    restored.context(:requirements).history.clear
    assert_equal 1, restored.context(:requirements).history.size
  end

  def test_store_keeps_what_each_context_writes_apart_from_its_history
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

    root.context(:development).store["result"] = {"kind"=>"build", "success"=>true}

    assert_equal({"kind"=>"build", "success"=>true}, root.context(:runtime).context(:development).store["result"])
    assert_empty root.context(:runtime).store
    assert_empty root.context(:development).history
  end

  def test_snapshot_restores_stores_without_sharing_mutable_values
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
    root.context(:development).store["result"] = {"kind"=>"build", "success"=>true}
    snapshot = root.snapshot
    root.context(:development).store["result"]["success"] = false

    restored = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [], state: snapshot)

    assert_equal true, restored.context(:development).store["result"]["success"]
  end

  def test_selection_state_does_not_include_stores
    root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])

    root.context(:development).store["result"] = {"kind"=>"build", "success"=>true}

    refute_includes JSON.generate(root.selection_state), "success"
    refute_includes JSON.generate(root.context(:development).messages), "success"
  end

  def test_thoughts_other_than_act_cannot_execute_tools
    [:explain, :ask, :check, :plan].each do |thought|
      klass = Class.new(Handbook::Controller)
      klass.define_method(thought) { render(:execute, tool: :bash) }
      root = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [])
      error = assert_raises(Handbook::GenerationError) { klass.new(conversation: root.context(:x), views_path: "/missing").process }
      assert_equal "act 以外の思考からツールは実行できません", error.message
    end
  end
end
