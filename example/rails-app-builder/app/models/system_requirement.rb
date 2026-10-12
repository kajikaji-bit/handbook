# frozen_string_literal: true
require "json_schemer"

SystemRequirement = Data.define(:functions, :qualities, :constraints) do
  self::PROMPT = <<~PROMPT
    会話から、利用者が伝えた要件を、機能（functions）・品質（qualities）・制約（constraints）に分けて一文ずつ書き出してください。
    利用者が伝えていないことは補わず、該当するものが無い分類は空の配列にしてください。
    JSON Schema に従い JSON だけを返してください。
  PROMPT
  self::SCHEMA = {
    type: "object", additionalProperties: false,
    required: %w[functions qualities constraints],
    properties: %w[functions qualities constraints].to_h { |key| [key.to_sym, { type: "array", items: { type: "string", minLength: 1 } }] }
  }.freeze

  def self.from(conversation, generator: Handbook::OpenRouterClient.new)
    text = generator.generate(prompt: "#{self::PROMPT}\n会話:\n#{JSON.generate(conversation.messages)}", schema: self::SCHEMA, schema_name: "system_requirement")
    data = JSON.parse(text)
    unless JSONSchemer.schema(JSON.parse(JSON.generate(self::SCHEMA))).valid?(data) && data.fetch("functions").any?
      raise Handbook::GenerationError, "要件を読み取れません"
    end
    conversation.store["system_requirement"] = data
    new(**data.transform_keys(&:to_sym))
  rescue JSON::ParserError
    raise Handbook::GenerationError, "要件を読み取れません"
  end

  def self.stored(conversation)
    data = conversation.context(:system_requirements).store["system_requirement"]
    return nil if data.nil?
    new(**data.transform_keys(&:to_sym))
  end
end
