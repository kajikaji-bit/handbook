# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../lib/handbook"

class JevClientTest < Minitest::Test
  class HTTP
    attr_reader :request_sent, :options
    def initialize(response)
      @response = response
    end
    def start(*args, **options)
      @options = options
      yield self
    end
    def request(request)
      @request_sent = request
      raise @response if @response.is_a?(Exception)
      @response
    end
  end

  def response(body, klass = Net::HTTPOK, code = "200")
    result = klass.new("1.1", code, "test")
    result.instance_variable_set(:@read, true)
    result.body = body
    result
  end

  def test_request_contract_and_typed_response_without_credential_logging
    log = StringIO.new
    answer = { "type" => "choice", "choice" => "runtime", "probabilities" => { "runtime" => 1 }, "confidence" => 1 }
    http = HTTP.new(response(JSON.generate(model: "test-model", answers: { selection: answer })))
    client = Handbook::JevClient.new(api_key: "test-only-secret", logger: log, http: http)
    assert_equal answer, client.choose(state: "起動して", instructions: "文脈を選ぶ", criteria: { runtime: "サーバーの起動" })
    request = http.request_sent
    body = JSON.parse(request.body)
    assert_equal "/v1/systemone", request.path
    assert_equal "Bearer test-only-secret", request["Authorization"]
    assert_equal "起動して", body["state"]
    assert_equal "choice", body.dig("questions", "selection", "type")
    assert_equal({ "runtime" => "サーバーの起動" }, body.dig("questions", "selection", "criteria"))
    assert_equal 30, http.options[:read_timeout]
    refute_includes log.string, "test-only-secret"
    assert_equal %w[jev_request jev_response], log.string.lines.map { |l| JSON.parse(l)["event"] }
  end

  def test_missing_key_and_bad_responses_are_explicit_failures
    assert_raises(ArgumentError) { Handbook::JevClient.new(api_key: "") }
    [Net::ReadTimeout.new, response("invalid"), response("{}"), response("private", Net::HTTPUnauthorized, "401")].each do |result|
      client = Handbook::JevClient.new(api_key: "test", http: HTTP.new(result))
      error = assert_raises(Handbook::JevError) { client.choose(state: "x", instructions: "x", criteria: { x: "x" }) }
      refute_includes error.message, "private"
    end
  end
end
