# frozen_string_literal: true
require "minitest/autorun"
require "shellwords"
require_relative "../config/application"

class ApplicationVerificationTest < Minitest::Test
  def item
    {"name"=>"記事を作成できる", "request"=>{"method"=>"POST", "path"=>"/posts", "body"=>{"post"=>{"title"=>"初投稿"}}}, "expect"=>{"status"=>201, "body"=>{"title"=>"初投稿"}}}
  end

  def conversation(state: nil, result: nil)
    Handbook::Conversation.new(id: "verification", messages: [{"role"=>"user", "content"=>"検証して"}], tools: [], state: state, tool_result: result)
  end

  def running(items: true)
    input = conversation
    input.context(:runtime).store["result"] = {"kind"=>"run", "success"=>true, "base_url"=>"http://127.0.0.1:3000"}
    input.context(:verification).store["verification_items"] = {"items"=>[item]} if items
    input
  end

  def started
    input = running
    ApplicationVerification.from(input).start
    input
  end

  def finished(input, items)
    data = {"kind"=>"verify", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>items.all? { |i| i["passed"] }, "items"=>items}
    ApplicationVerification.from(conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}"}).context(:verification))
  end

  def test_start_records_the_command_as_running_and_command_passes_the_url_and_items
    input = running
    assert_nil ApplicationVerification.from(input).start
    assert_equal "verify", input.pending_tool["kind"]
    args = Shellwords.split(ApplicationVerification.from(input).command)
    assert_equal File.join(ApplicationVerification::APP_ROOT, "bin", "verify-app"), args[1]
    assert_equal input.pending_tool["token"], args[args.index("--token") + 1]
    assert_equal ApplicationBuild::OUTPUT, args[args.index("--app") + 1]
    assert_equal "http://127.0.0.1:3000", args[args.index("--url") + 1]
    assert_equal [item], JSON.parse(args[args.index("--items-json") + 1])
  end

  def test_missing_names_the_absent_startup_or_items
    assert_equal "起動が完了していません", ApplicationVerification.from(conversation).missing
    assert_equal "検証項目がありません", ApplicationVerification.from(running(items: false)).missing
    assert_nil ApplicationVerification.from(running).missing
  end

  def test_start_raises_without_a_successful_startup
    error = assert_raises(Handbook::GenerationError) { ApplicationVerification.from(conversation).start }
    assert_equal "起動が完了していません", error.message
  end

  def test_start_raises_without_stored_items
    error = assert_raises(Handbook::GenerationError) { ApplicationVerification.from(running(items: false)).start }
    assert_equal "検証項目がありません", error.message
  end

  def test_command_raises_before_start
    error = assert_raises(Handbook::GenerationError) { ApplicationVerification.from(running).command }
    assert_equal "検証を開始していません", error.message
  end

  def test_succeeded_only_when_every_item_passed
    passed = finished(started, [{"name"=>"記事を作成できる", "status"=>201, "passed"=>true}])
    assert passed.finished?
    assert passed.succeeded?
    failed = finished(started, [{"name"=>"記事を作成できる", "status"=>201, "passed"=>true}, {"name"=>"記事を一覧できる", "status"=>404, "passed"=>false}])
    assert failed.finished?
    refute failed.succeeded?
  end

  def test_success_flag_without_item_results_is_not_succeeded
    input = started
    data = {"kind"=>"verify", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true, "items"=>[{"name"=>"記事を作成できる", "passed"=>false}]}
    verification = ApplicationVerification.from(conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}"}).context(:verification))
    refute verification.succeeded?
  end

  def test_from_writes_the_received_result_to_the_store
    input = started
    data = {"kind"=>"verify", "token"=>input.pending_tool["token"], "app"=>ApplicationBuild::OUTPUT, "success"=>true, "items"=>[{"name"=>"記事を作成できる", "passed"=>true}]}
    after = conversation(state: input.snapshot, result: {"content"=>"HANDBOOK_RESULT=#{JSON.generate(data)}"})

    ApplicationVerification.from(after.context(:verification))

    assert_equal true, after.context(:verification).store["result"]["success"]
  end
end
