# frozen_string_literal: true
require "minitest/autorun"
require_relative "../config/application"

class VerificationItemsTest < Minitest::Test
  Generator = Struct.new(:result, :calls) do
    def model; "fake"; end
    def generate(**args); calls << args; result; end
  end

  def conversation
    Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"POST /posts で記事を作成すると 201 が返ること"}], tools: [])
  end

  def item
    {"name"=>"記事を作成できる", "request"=>{"method"=>"POST", "path"=>"/posts", "body"=>{"post"=>{"title"=>"初投稿"}}}, "expect"=>{"status"=>201, "body"=>{"title"=>"初投稿"}}}
  end

  def generated(entry)
    entry.merge("request" => entry["request"].merge("body" => JSON.generate(entry["request"]["body"])),
                "expect" => entry["expect"].merge("body" => JSON.generate(entry["expect"]["body"])))
  end

  def test_from_maps_the_user_message_to_requests_and_expected_responses
    generator = Generator.new(JSON.generate(items: [generated(item)]), [])
    items = VerificationItems.from(conversation.context(:verification), generator: generator)
    assert_equal ["記事を作成できる"], items.to_a.map(&:name)
    assert_equal "POST", items.to_a.first.request["method"]
    assert_equal({"post"=>{"title"=>"初投稿"}}, items.to_a.first.request["body"])
    assert_equal 201, items.to_a.first.expect["status"]
    assert_equal({"title"=>"初投稿"}, items.to_a.first.expect["body"])
    assert_equal [item], items.data["items"]
    assert_equal VerificationItems::GENERATION_SCHEMA, generator.calls.first[:schema]
    assert_equal "verification_items", generator.calls.first[:schema_name]
  end

  def test_generation_schema_asks_for_bodies_as_json_strings
    entry = VerificationItems::GENERATION_SCHEMA.dig(:properties, :items, :items, :properties)
    assert_equal "string", entry.dig(:request, :properties, :body, :type)
    assert_equal "string", entry.dig(:expect, :properties, :body, :type)
  end

  def test_from_reads_empty_bodies_as_empty_objects
    listing = {"name"=>"記事を一覧できる", "request"=>{"method"=>"GET", "path"=>"/posts", "body"=>""}, "expect"=>{"status"=>200, "body"=>" "}}
    generator = Generator.new(JSON.generate(items: [listing]), [])
    items = VerificationItems.from(conversation.context(:verification), generator: generator)
    assert_equal({}, items.to_a.first.request["body"])
    assert_equal({}, items.to_a.first.expect["body"])
  end

  def test_from_rejects_bodies_that_are_not_json_objects
    ["{", "[1]"].each do |body|
      broken = generated(item)
      broken["request"]["body"] = body
      generator = Generator.new(JSON.generate(items: [broken]), [])
      assert_raises(Handbook::GenerationError) { VerificationItems.from(conversation.context(:verification), generator: generator) }
    end
  end

  def test_from_raises_when_no_item_is_mapped
    generator = Generator.new(JSON.generate(items: []), [])
    error = assert_raises(Handbook::GenerationError) { VerificationItems.from(conversation.context(:verification), generator: generator) }
    assert_equal "検証項目を読み取れません", error.message
  end

  def test_from_rejects_unknown_methods_and_relative_paths
    [->(i) { i["request"]["method"] = "TRACE" }, ->(i) { i["request"]["path"] = "posts" }].each do |mutate|
      broken = item
      mutate.call(broken)
      generator = Generator.new(JSON.generate(items: [generated(broken)]), [])
      error = assert_raises(Handbook::GenerationError) { VerificationItems.from(conversation.context(:verification), generator: generator) }
      assert_equal "検証項目の形式が不正です", error.message
    end
  end

  def test_stored_returns_the_items_stored_by_the_verification_context
    input = conversation
    assert_nil VerificationItems.stored(input)
    input.context(:verification).store["verification_items"] = {"items"=>[item]}
    assert_equal ["記事を作成できる"], VerificationItems.stored(input).to_a.map(&:name)
  end

  def test_from_writes_the_items_to_the_store_of_the_context
    input = conversation
    generator = Generator.new(JSON.generate(items: [generated(item)]), [])

    VerificationItems.from(input.context(:verification), generator: generator)

    assert_equal [item], input.context(:verification).store["verification_items"]["items"]
    assert_equal ["記事を作成できる"], VerificationItems.stored(input).to_a.map(&:name)
  end
end
