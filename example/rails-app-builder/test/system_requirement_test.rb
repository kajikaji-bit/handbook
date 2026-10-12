# frozen_string_literal: true
require "minitest/autorun"
require_relative "../config/application"

class SystemRequirementTest < Minitest::Test
  Generator = Struct.new(:result, :calls) do
    def model; "fake"; end
    def generate(**args); calls << args; result; end
  end

  def conversation
    Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"記事を作成して一覧できること。JSON で応答すること。"}], tools: [])
  end

  def test_from_maps_the_user_message_to_functions_qualities_and_constraints
    generator = Generator.new(JSON.generate(functions: ["記事を作成する", "記事を一覧する"], qualities: [], constraints: ["JSON で応答する"]), [])
    system_requirement = SystemRequirement.from(conversation.context(:system_requirements), generator: generator)
    assert_equal ["記事を作成する", "記事を一覧する"], system_requirement.functions
    assert_equal [], system_requirement.qualities
    assert_equal ["JSON で応答する"], system_requirement.constraints
    assert_equal SystemRequirement::SCHEMA, generator.calls.first[:schema]
    assert_equal "system_requirement", generator.calls.first[:schema_name]
  end

  def test_from_raises_when_no_function_is_mapped
    generator = Generator.new(JSON.generate(functions: [], qualities: ["速い"], constraints: []), [])
    error = assert_raises(Handbook::GenerationError) { SystemRequirement.from(conversation.context(:system_requirements), generator: generator) }
    assert_equal "要件を読み取れません", error.message
  end

  def test_stored_returns_the_system_requirement_stored_by_the_system_requirements_context
    input = conversation
    assert_nil SystemRequirement.stored(input)
    input.context(:system_requirements).store["system_requirement"] = {"functions"=>["記事を作成する"], "qualities"=>[], "constraints"=>[]}
    assert_equal ["記事を作成する"], SystemRequirement.stored(input).functions
  end

  def test_from_writes_the_system_requirement_to_the_store_of_the_context
    input = conversation
    generator = Generator.new(JSON.generate(functions: ["記事を作成する"], qualities: [], constraints: []), [])

    SystemRequirement.from(input.context(:system_requirements), generator: generator)

    assert_equal ["記事を作成する"], SystemRequirement.stored(input.context(:development)).functions
  end
end
