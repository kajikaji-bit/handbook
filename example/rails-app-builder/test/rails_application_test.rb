# frozen_string_literal: true

require "minitest/autorun"
require_relative "../config/application"

class RailsApplicationTest < Minitest::Test
  class Judgment
    attr_reader :calls
    def initialize(choice)
      @choice, @calls = choice, []
    end
    def choose(**args)
      @calls << args
      raise @choice if @choice.is_a?(Exception)
      { "choice" => @choice, "confidence" => 1.0, "probabilities" => { @choice => 1.0 } }
    end
  end

  def conversation(text)
    Handbook::Conversation.new(id: "model-test", messages: [{ "role" => "user", "content" => text }], tools: [])
  end

  def test_predicate_returns_boolean_and_memoizes_both_outcomes
    { "defined" => true, "undefined" => false }.each do |choice, expected|
      judgment = Judgment.new(choice)
      input = conversation("利用者の要望")
      application = RailsApplication.from(input, judgment: judgment)
      assert_empty judgment.calls
      2.times { assert_equal expected, application.requirements_defined? }
      assert_equal 1, judgment.calls.size
      assert_equal input.messages, JSON.parse(judgment.calls.first[:state])
      assert_equal %w[defined undefined], judgment.calls.first[:criteria].keys
      assert_equal choice, application.requirements_judgment.fetch("choice")
    end
  end

  def test_error_never_becomes_false_or_a_recorded_success
    ["unknown", Handbook::JevError.new("connection failed")].each do |result|
      input = conversation("要望")
      application = RailsApplication.from(input, judgment: Judgment.new(result))
      assert_raises(Handbook::JevError) { application.requirements_defined? }
      assert_empty input.histories
    end
  end

  def test_new_application_does_not_reuse_another_conversations_result
    judgment = Judgment.new("defined")
    first, second = conversation("要望1"), conversation("要望2")
    RailsApplication.from(first, judgment: judgment).requirements_defined?
    assert_empty second.histories
    RailsApplication.from(second, judgment: judgment).requirements_defined?
    assert_equal ["要望1", "要望2"], judgment.calls.map { |c| JSON.parse(c[:state]).first["content"] }
  end
end
