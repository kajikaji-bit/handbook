require "minitest/autorun"
require_relative "../lib/handbook"
class StreamTest < Minitest::Test
  def request(app)
    server = Handbook::Server.new(application: app, model: "test")
    env = Rack::MockRequest.env_for("/", method: "POST", input: JSON.generate(messages: [{role: "user", content: "x"}]))
    env["HTTP_X_SESSION_AFFINITY"] = "stream"
    server.call(env)
  end

  def test_partial_response_arrives_before_design_and_only_last_finishes
    generated = false
    app = ->(conversation, &emit) {
      emit.call(Handbook::Reply.message("判断"))
      generated = true
      emit.call(Handbook::Reply.finish("設計"))
    }
    status, _, body = request(app)
    assert_equal 200, status
    refute generated
    chunks = []
    body.each do |chunk|
      refute generated if chunks.empty?
      chunks << chunk
    end
    assert generated
    parsed = chunks[0...-1].map { |c| JSON.parse(c.delete_prefix("data: ")) }
    assert_equal [nil, nil, "stop"], parsed.map { |c| c["choices"][0]["finish_reason"] }
    assert_equal ["判断", "\n\n設計"], parsed.filter_map { |c| c.dig("choices",0,"delta","content") }
  end

  def test_failure_after_partial_response_is_not_normal_completion
    app = ->(conversation, &emit) { emit.call(Handbook::Reply.message("判断")); raise Handbook::GenerationError, "private" }
    status, _, body = request(app)
    assert_equal 200, status
    text = body.to_a.join
    assert_includes text, "upstream_error"
    refute_includes text, '"finish_reason":"stop"'
    refute_includes text, "private"
  end

  def test_disconnect_does_not_continue_generation
    generated = false
    app = ->(conversation, &emit) { emit.call(Handbook::Reply.message("判断")); generated = true }
    _, _, body = request(app)
    body.close
    refute generated
  end
end
