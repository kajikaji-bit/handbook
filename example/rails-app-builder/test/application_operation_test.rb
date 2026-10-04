# frozen_string_literal: true
require "minitest/autorun"
require_relative "../config/application"

class ApplicationOperationTest < Minitest::Test
  def conversation(state: nil, result: nil)
    Handbook::Conversation.new(id: "operations", messages: [{"role"=>"user","content"=>"作って"}], tools: [], state: state, tool_result: result)
  end

  def pending
    input = conversation
    input.context(:resource_design).record(:perceive, text: "設計", data: {"resources"=>[],"unresolved"=>[]})
    input.context(:requirements).record(:judge, text: "検証まで", data: {outcome: "verify"})
    command = ApplicationBuild.from(input).command
    args = Shellwords.split(command)
    assert_equal ApplicationOperation::OUTPUT, args[args.index("--output")+1]
    assert_equal ResourceDesign.recorded(input), JSON.parse(args[args.index("--design-json")+1])
    input
  end

  def test_result_restores_observations_and_allows_next_operation
    input = pending
    data = {"kind"=>"build","token"=>input.pending_tool["token"],"app"=>ApplicationOperation::OUTPUT,"success"=>true}
    resumed = conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}\n"})
    build = ApplicationBuild.from(resumed)
    assert build.succeeded?
    refute build.request_complete?
    assert_nil resumed.pending_tool
    resumed.context(:development).record(:perceive, text: "生成成功", data: {result: build.result})
    assert_includes ApplicationRuntime.from(resumed).command, "/bin/start-app"
    assert_equal "build", resumed.context(:development).latest(:perceive).dig("result", "kind")
  end

  def test_invalid_or_failed_results_never_become_success
    %w[token kind app malformed failed].each do |mutation|
      input = pending
      data = {"kind"=>"build","token"=>input.pending_tool["token"],"app"=>ApplicationOperation::OUTPUT,"success"=>true}
      data[mutation] = "wrong" if %w[token kind app].include?(mutation)
      data["success"] = false if mutation == "failed"
      content = mutation == "malformed" ? "HANDBOOK_RESULT={" : "HANDBOOK_RESULT=#{JSON.generate(data)}"
      resumed = conversation(state: input.snapshot, result: {"content"=>content})
      build = ApplicationBuild.from(resumed)
      assert build.result_available?
      refute build.succeeded?
      assert_raises(Handbook::GenerationError) { ApplicationRuntime.from(resumed).command }
    end
  end

  def test_execution_requires_prior_evidence_and_new_requests_start_empty
    assert_raises(Handbook::GenerationError) { ApplicationBuild.from(conversation).command }
    input = pending
    assert_raises(Handbook::GenerationError) { ApplicationVerification.from(input).command }
    assert_empty conversation.histories
    assert_nil conversation.pending_tool
  end
end
