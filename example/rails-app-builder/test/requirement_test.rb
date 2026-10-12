# frozen_string_literal: true
require "minitest/autorun"
require_relative "../config/application"

class RequirementTest < Minitest::Test
  Generator = Struct.new(:result, :calls) do
    def model; "fake"; end
    def generate(**args); calls << args; result; end
  end

  def conversation
    Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"記事を投稿して、一覧と詳細で読めるブログが欲しい"}], tools: [])
  end

  def test_from_maps_the_user_message_to_statements_with_the_schema
    generator = Generator.new(JSON.generate(statements: ["記事を投稿して、一覧と詳細で読めるブログが欲しい"]), [])
    requirement = Requirement.from(conversation.context(:requirements), generator: generator)
    assert_equal ["記事を投稿して、一覧と詳細で読めるブログが欲しい"], requirement.statements
    assert_equal Requirement::SCHEMA, generator.calls.first[:schema]
    assert_equal "requirement", generator.calls.first[:schema_name]
    assert_includes generator.calls.first[:prompt], "一覧と詳細で読めるブログ"
  end

  def test_from_raises_when_no_statement_is_mapped
    generator = Generator.new(JSON.generate(statements: []), [])
    error = assert_raises(Handbook::GenerationError) { Requirement.from(conversation.context(:requirements), generator: generator) }
    assert_equal "要求を読み取れません", error.message
  end

  def test_stored_returns_the_requirement_stored_by_the_requirements_context
    input = conversation
    assert_nil Requirement.stored(input)
    input.context(:requirements).store["requirement"] = {"statements"=>["ブログが欲しい"]}
    assert_equal ["ブログが欲しい"], Requirement.stored(input).statements
  end

  def test_from_writes_the_requirement_to_the_store_of_the_context
    input = conversation
    generator = Generator.new(JSON.generate(statements: ["ブログが欲しい"]), [])

    Requirement.from(input.context(:requirements), generator: generator)

    assert_equal ["ブログが欲しい"], Requirement.stored(input.context(:development)).statements
  end
end
