require "minitest/autorun"
require "tmpdir"
require_relative "../lib/handbook"

class GenerationTest < Minitest::Test
  class HTTP
    attr_reader :sent, :options
    def initialize(response); @response = response; end
    def start(*, **options); @options = options; yield self; end
    def request(request); @sent = request; raise @response if @response.is_a?(Exception); @response; end
  end

  def response(body, code = "200")
    result = (code == "200" ? Net::HTTPOK : Net::HTTPUnauthorized).new("1.1", code, "test")
    result.instance_variable_set(:@read, true)
    result.body = body
    result
  end

  def test_openrouter_contract
    http = HTTP.new(response(JSON.generate(choices: [{ message: { content: "質問です" }, finish_reason: "stop" }])))
    client = Handbook::OpenRouterClient.new(api_key: "test-key", model: "test-model", http: http)
    assert_equal "質問です", client.generate(prompt: "会話")
    assert_equal "/api/v1/chat/completions", http.sent.path
    assert_equal "Bearer test-key", http.sent["Authorization"]
    assert_equal({"model"=>"test-model", "stream"=>false, "messages"=>[{"role"=>"user", "content"=>"会話"}]}, JSON.parse(http.sent.body))
    assert_equal 60, http.options[:read_timeout]
  end

  def test_json_schema_is_sent_only_when_requested
    http = HTTP.new(response(JSON.generate(choices: [{ message: { content: "{}" }, finish_reason: "stop" }])))
    client = Handbook::OpenRouterClient.new(api_key: "test", http: http)
    schema = {type: "object", additionalProperties: false, properties: {}, required: []}
    client.generate(prompt: "設計", schema: schema, schema_name: "resource_design")
    body = JSON.parse(http.sent.body)
    assert_equal "json_schema", body.dig("response_format", "type")
    assert_equal true, body.dig("response_format", "json_schema", "strict")
    assert_equal JSON.parse(JSON.generate(schema)), body.dig("response_format", "json_schema", "schema")
    assert_equal true, body.dig("provider", "require_parameters")
    client.generate(prompt: "文章")
    refute JSON.parse(http.sent.body).key?("response_format")
  end

  def test_invalid_or_failed_generation_is_not_success
    bodies = ["bad", "null", "{}", '{"choices":[]}', JSON.generate(choices: [{ message: { content: "" }, finish_reason: "stop" }]), JSON.generate(choices: [{ message: { content: "途中" }, finish_reason: "length" }])]
    (bodies.map { |body| response(body) } + [response("private", "401"), Net::ReadTimeout.new]).each do |result|
      client = Handbook::OpenRouterClient.new(api_key: "test", http: HTTP.new(result))
      error = assert_raises(Handbook::GenerationError) { client.generate(prompt: "x") }
      refute_includes error.message, "private"
    end
  end

  def test_missing_view_variable_and_template_fail_before_generation
    generator = Object.new
    def generator.generate(**); raise "must not call"; end
    Dir.mktmpdir do |dir|
      path = File.join(dir, "view.erb")
      File.write(path, '<%= @missing %>')
      assert_raises(Handbook::GenerationError) { Handbook::GeneratedView.new(path: path, generator: generator).render(assigns: {}) }
      assert_raises(Handbook::GenerationError) { Handbook::GeneratedView.new(path: path + '.absent', generator: generator).render(assigns: {}) }
    end
  end
end
