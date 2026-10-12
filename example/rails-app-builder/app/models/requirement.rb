# frozen_string_literal: true
require "json_schemer"

Requirement = Data.define(:statements) do
  self::PROMPT = <<~PROMPT
    会話から、利用者が欲しいと伝えたこと（要求）を一文ずつ書き出してください。
    利用者が伝えていないことは補わないでください。
    JSON Schema に従い JSON だけを返してください。
  PROMPT
  self::SCHEMA = {
    type: "object", additionalProperties: false,
    required: %w[statements],
    properties: { statements: { type: "array", items: { type: "string", minLength: 1 } } }
  }.freeze

  def self.from(conversation, generator: Handbook::OpenRouterClient.new)
    text = generator.generate(prompt: "#{self::PROMPT}\n会話:\n#{JSON.generate(conversation.messages)}", schema: self::SCHEMA, schema_name: "requirement")
    data = JSON.parse(text)
    unless JSONSchemer.schema(JSON.parse(JSON.generate(self::SCHEMA))).valid?(data) && data.fetch("statements").any?
      raise Handbook::GenerationError, "要求を読み取れません"
    end
    conversation.store["requirement"] = data
    new(statements: data.fetch("statements"))
  rescue JSON::ParserError
    raise Handbook::GenerationError, "要求を読み取れません"
  end

  def self.stored(conversation)
    data = conversation.context(:requirements).store["requirement"]
    return nil if data.nil?
    new(statements: data.fetch("statements"))
  end
end
