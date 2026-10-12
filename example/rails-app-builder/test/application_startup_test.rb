# frozen_string_literal: true
require "minitest/autorun"
require "shellwords"
require_relative "../config/application"

class ApplicationStartupTest < Minitest::Test
  def conversation(state: nil, result: nil)
    Handbook::Conversation.new(id: "startup", messages: [{"role"=>"user", "content"=>"起動して"}], tools: [], state: state, tool_result: result)
  end

  def built
    input = conversation
    input.context(:development).store["result"] = {"kind"=>"build", "app"=>ApplicationBuild::OUTPUT, "success"=>true}
    input
  end

  def started
    input = built
    ApplicationStartup.from(input).start
    input
  end

  def test_start_records_the_command_as_running_and_command_returns_the_startup_command
    input = built
    assert_nil ApplicationStartup.from(input).start
    assert_equal "run", input.pending_tool["kind"]
    args = Shellwords.split(ApplicationStartup.from(input).command)
    assert_equal File.join(ApplicationStartup::APP_ROOT, "bin", "start-app"), args[1]
    assert_equal input.pending_tool["token"], args[args.index("--token") + 1]
    assert_equal ApplicationBuild::OUTPUT, args[args.index("--app") + 1]
    assert_equal "3000", args[args.index("--port") + 1]
  end

  def test_missing_names_the_absent_successful_build
    assert_equal "構築が完了していません", ApplicationStartup.from(conversation).missing
    assert_nil ApplicationStartup.from(built).missing
  end

  def test_start_raises_without_a_successful_build
    error = assert_raises(Handbook::GenerationError) { ApplicationStartup.from(conversation).start }
    assert_equal "構築が完了していません", error.message
    input = conversation
    input.context(:development).store["result"] = {"kind"=>"build", "success"=>false}
    assert_raises(Handbook::GenerationError) { ApplicationStartup.from(input).start }
  end

  def test_command_raises_before_start
    error = assert_raises(Handbook::GenerationError) { ApplicationStartup.from(built).command }
    assert_equal "起動を開始していません", error.message
  end

  def test_from_reads_the_matching_result_and_exposes_the_url
    input = started
    data = {"kind"=>"run", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true, "base_url"=>"http://127.0.0.1:3000"}
    startup = ApplicationStartup.from(conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}"}).context(:runtime))
    assert startup.finished?
    assert startup.succeeded?
    assert_equal "http://127.0.0.1:3000", startup.url
  end

  def test_url_is_nil_without_a_result
    startup = ApplicationStartup.from(started)
    refute startup.finished?
    assert_nil startup.url
  end

  def test_mismatched_token_never_becomes_success
    input = started
    data = {"kind"=>"run", "token"=>"wrong", "app"=>ApplicationBuild::OUTPUT, "success"=>true, "base_url"=>"http://127.0.0.1:3000"}
    startup = ApplicationStartup.from(conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}"}).context(:runtime))
    refute startup.succeeded?
    assert_equal "コマンドの結果を照合できませんでした", startup.result["error"]
  end

  def test_from_writes_the_received_result_to_the_store_for_the_verification
    input = started
    data = {"kind"=>"run", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true, "base_url"=>"http://127.0.0.1:3000"}
    after = conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}"})
    ApplicationStartup.from(after.context(:runtime))
    after.context(:verification).store["verification_items"] = {"items"=>[{"name"=>"記事を作成できる", "request"=>{"method"=>"GET", "path"=>"/posts"}, "expect"=>{"status"=>200}}]}

    later = conversation(state: after.snapshot)

    assert_equal "http://127.0.0.1:3000", later.context(:runtime).store["result"]["base_url"]
    assert_nil ApplicationVerification.from(later.context(:verification)).missing
  end
end
