require "minitest/autorun"
require "tmpdir"
require_relative "../lib/handbook"

class ContextHistoryTest < Minitest::Test
  class Controller < Handbook::Controller
    def perceive
      @topic = conversation.user_message
      render :perception
    end
    def judge
      render json: {ready: true}
    end
    def act
      render text: "利用者への表示", finish: true
    end
  end

  def input(state: nil)
    Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"依頼"}], tools: [], state: state)
  end

  def test_internal_render_is_scoped_and_not_emitted_to_pi
    root = input
    root.context(:other).record(:judge, text: "別の判断", data: {ready: false})
    sent=[]
    Dir.mktmpdir do |path|
      File.write(File.join(path,"perception.txt.erb"), "読み取った要求: <%= @topic %>")
      Controller.new(conversation: root.context(:requirements), views_path: path, responder: ->(r) { sent << r }).process
    end
    assert_equal ["利用者への表示"], sent.map(&:text)
    assert_equal [:finish], sent.map(&:kind)
    scoped = root.context(:requirements)
    assert_equal %w[perceive judge act], scoped.history.map { |e| e["phase"] }
    assert_equal "読み取った要求: 依頼", scoped.perceptions.first["text"]
    assert_equal true, scoped.latest(:judge)["ready"]
    refute_includes scoped.messages.map { |e| e["content"] }, "別の判断"
    assert_equal false, scoped.context(:other).latest(:judge)["ready"]
    assert_equal ["依頼"], root.messages.map { |e| e["content"] }
    assert root.selection_state[:contexts].key?("other")
  end

  def test_snapshot_restores_histories_without_sharing_mutable_values
    root=input
    root.context(:requirements).record(:judge, text: "定義済み", data: {ready: true})
    root.pending_tool={"kind"=>"build","token"=>"token"}
    snapshot=root.snapshot
    root.context(:requirements).record(:judge, text: "後の判断")
    restored=input(state: snapshot)
    assert_equal 1, restored.context(:requirements).judgments.size
    assert_equal true, restored.context(:requirements).latest(:judge)["ready"]
    assert_equal "token",restored.pending_tool["token"]
    restored.context(:requirements).history.clear
    assert_equal 1,restored.context(:requirements).history.size
    assert_empty input.histories
  end

  def test_internal_phases_cannot_execute_tools_or_finish
    [:perceive, :judge].each do |phase|
      [ {tool: :bash}, {finish: true} ].each do |options|
        klass=Class.new(Handbook::Controller)
        klass.define_method(phase) { render(:execute, **options) }
        assert_raises(Handbook::GenerationError) { klass.new(conversation: input.context(:x), views_path: "/missing").process }
      end
    end
  end
end
