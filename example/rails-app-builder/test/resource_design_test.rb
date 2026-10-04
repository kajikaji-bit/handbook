require "minitest/autorun"
require_relative "../config/application"

class ResourceDesignTest < Minitest::Test
  def data
    {"resources"=>[{"name"=>"Post", "label"=>"記事", "attributes"=>[{"name"=>"title", "type"=>"string"}, {"name"=>"body", "type"=>"text"}], "operations"=>%w[create index show]}], "unresolved"=>[]}
  end

  def test_valid_design_is_available_to_fixed_view
    design = ResourceDesign.from_json(JSON.generate(data))
    assert_equal "Post", design.resources.first.name
    path = File.expand_path("../app/views/resource_design/show.txt.erb", __dir__)
    text = Handbook::Template.render(path: path, assigns: {resource_design: design})
    assert_includes text, "title: 文字列"
    assert_includes text, "body: 長文"
    assert_includes text, "作成"
  end

  def test_non_blog_resource_and_operations_render_without_blog_labels
    d = data
    d["resources"] = [{"name"=>"Task", "label"=>"タスク", "attributes"=>[{"name"=>"title", "type"=>"string"}, {"name"=>"completed", "type"=>"boolean"}], "operations"=>%w[create index update destroy]}]
    design = ResourceDesign.from_json(JSON.generate(d))
    text = Handbook::Template.render(path: File.expand_path("../app/views/resource_design/show.txt.erb", __dir__), assigns: {resource_design: design})
    assert_includes text, "Task（タスク）"
    assert_includes text, "completed: 真偽値"
    assert_includes text, "更新"
    assert_includes text, "削除"
    refute_includes text, "投稿"
    refute_includes text, "記事"
  end

  def test_schema_and_domain_validation_reject_invalid_designs
    mutations = [
      ->(d) { d["extra"] = true },
      ->(d) { d["resources"][0]["name"] = "Post;rm" },
      ->(d) { d["resources"][0]["attributes"][0]["type"] = "executable" },
      ->(d) { d["resources"][0]["attributes"][0]["name"] = "type" },
      ->(d) { d["resources"][0]["attributes"] *= 2 },
      ->(d) { d["resources"][0]["operations"] << "execute" },
      ->(d) { d["resources"] = [] },
      ->(d) { d["unresolved"] = ["本文が必要か不明"] }
    ]
    mutations.each do |mutate|
      d = data; mutate.call(d)
      assert_raises(Handbook::GenerationError) { ResourceDesign.from_json(JSON.generate(d)) }
    end
    assert_raises(Handbook::GenerationError) { ResourceDesign.from_json("broken") }
  end

  def test_schema_is_sent_and_unconfirmed_requirements_never_generate
    generator = Struct.new(:result, :calls) do
      def model; "fake"; end
      def generate(**args); calls << args; result; end
    end.new(JSON.generate(data), [])
    conversation = Handbook::Conversation.new(id: "x", messages: [{"role"=>"user", "content"=>"ブログ"}], tools: [])
    assert_raises(Handbook::GenerationError) { ResourceDesign.from(conversation, generator: generator) }
    assert_empty generator.calls
    conversation.context(:requirements).record(:judge, text: "要求は定義済み", data: {requirements: {choice: "defined"}})
    design = ResourceDesign.from(conversation, generator: generator)
    assert_equal ResourceDesign::SCHEMA, generator.calls.first[:schema]
    assert_equal "resource_design", generator.calls.first[:schema_name]
    assert_equal data, design.data
  end
end
