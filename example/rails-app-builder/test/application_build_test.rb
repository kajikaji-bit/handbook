# frozen_string_literal: true
require "minitest/autorun"
require "shellwords"
require_relative "../config/application"

class ApplicationBuildTest < Minitest::Test
  def design
    {"resources"=>[{"name"=>"Post", "label"=>"記事", "attributes"=>[{"name"=>"title", "type"=>"string"}], "operations"=>%w[create]}], "unresolved"=>[]}
  end

  def conversation(state: nil, result: nil)
    Handbook::Conversation.new(id: "build", messages: [{"role"=>"user", "content"=>"構築して"}], tools: [], state: state, tool_result: result)
  end

  def started
    input = conversation
    input.context(:resource_design).store["resource_design"] = design
    ApplicationBuild.from(input).start
    input
  end

  def resumed(input, content)
    conversation(state: input.snapshot, result: {"content"=>content})
  end

  def test_start_records_the_command_as_running_and_returns_nil
    input = conversation
    input.context(:resource_design).store["resource_design"] = design
    assert_nil ApplicationBuild.from(input).start
    assert_equal "build", input.pending_tool["kind"]
    refute_empty input.pending_tool["token"]
  end

  def test_missing_names_the_absent_resource_design
    assert_equal "構築するリソース設計がありません", ApplicationBuild.from(conversation).missing
    assert_nil ApplicationBuild.from(started).missing
  end

  def test_start_raises_without_a_stored_resource_design
    error = assert_raises(Handbook::GenerationError) { ApplicationBuild.from(conversation).start }
    assert_equal "構築するリソース設計がありません", error.message
  end

  def test_command_returns_the_build_command_without_changing_state
    input = started
    pending = input.pending_tool.dup
    args = Shellwords.split(ApplicationBuild.from(input).command)
    assert_equal File.join(ApplicationBuild::APP_ROOT, "bin", "build-app"), args[1]
    assert_equal pending["token"], args[args.index("--token") + 1]
    assert_equal ApplicationBuild::OUTPUT, args[args.index("--output") + 1]
    assert_equal design, JSON.parse(args[args.index("--design-json") + 1])
    assert_equal pending, input.pending_tool
  end

  def test_command_raises_before_start
    input = conversation
    input.context(:resource_design).store["resource_design"] = design
    error = assert_raises(Handbook::GenerationError) { ApplicationBuild.from(input).command }
    assert_equal "構築を開始していません", error.message
  end

  def test_from_reads_the_matching_result_and_clears_the_running_command
    input = started
    data = {"kind"=>"build", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true}
    after = resumed(input, "log\nHANDBOOK_RESULT=#{JSON.generate(data)}\n")
    build = ApplicationBuild.from(after.context(:development))
    assert build.finished?
    assert build.succeeded?
    assert_equal true, build.result["success"]
    assert_nil after.pending_tool
  end

  def test_from_without_a_result_is_not_finished
    build = ApplicationBuild.from(started)
    assert_nil build.result
    refute build.finished?
    refute build.succeeded?
  end

  def test_mismatched_or_missing_results_never_become_success
    %w[token kind app missing].each do |mutation|
      input = started
      data = {"kind"=>"build", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true}
      data[mutation] = "wrong" unless mutation == "missing"
      content = mutation == "missing" ? "log only\n" : "HANDBOOK_RESULT=#{JSON.generate(data)}"
      build = ApplicationBuild.from(resumed(input, content).context(:development))
      assert build.finished?
      refute build.succeeded?
      assert_equal "コマンドの結果を照合できませんでした", build.result["error"]
    end
  end

  def test_failed_result_is_finished_but_not_succeeded
    input = started
    data = {"kind"=>"build", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>false, "error"=>"rails new に失敗しました"}
    build = ApplicationBuild.from(resumed(input, "HANDBOOK_RESULT=#{JSON.generate(data)}").context(:development))
    assert build.finished?
    refute build.succeeded?
  end

  def test_from_writes_the_received_result_to_the_store_for_later_turns
    input = started
    data = {"kind"=>"build", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true}
    after = resumed(input, "HANDBOOK_RESULT=#{JSON.generate(data)}")
    ApplicationBuild.from(after.context(:development))

    later = conversation(state: after.snapshot)

    refute ApplicationBuild.from(later.context(:development)).finished?
    assert_equal true, later.context(:development).store["result"]["success"]
    assert_nil ApplicationStartup.from(later.context(:runtime)).missing
  end
end
