# frozen_string_literal: true
require "json_schemer"

class VerificationItems
  Item = Data.define(:name, :request, :expect)
  PROMPT = <<~PROMPT
    会話から、利用者が伝えた検証項目を書き出してください。
    検証項目ごとに、名前、API へ送るリクエスト（メソッド・パス・本文）、期待する応答（ステータス・本文に含まれるべき値）を書きます。
    利用者が伝えていない項目や期待は補わないでください。
    本文は JSON のオブジェクトを文字列にして書き、本文が無いときは "{}" にしてください。
    期待する応答の本文は、応答の JSON に含まれるべきキーと値のオブジェクトにします。たとえば title が「初投稿」であることを期待するなら "{\"title\": \"初投稿\"}" と書き、値だけの "初投稿" とは書きません。
    JSON Schema に従い JSON だけを返してください。
  PROMPT
  METHODS = %w[GET POST PATCH PUT DELETE].freeze
  SCHEMA = {
    type: "object", additionalProperties: false,
    required: %w[items],
    properties: {
      items: {
        type: "array",
        items: {
          type: "object", additionalProperties: false,
          required: %w[name request expect],
          properties: {
            name: { type: "string", minLength: 1 },
            request: {
              type: "object", additionalProperties: false,
              required: %w[method path body],
              properties: { method: { type: "string" }, path: { type: "string" }, body: { type: "object" } }
            },
            expect: {
              type: "object", additionalProperties: false,
              required: %w[status body],
              properties: { status: { type: "integer" }, body: { type: "object" } }
            }
          }
        }
      }
    }
  }.freeze
  # strict な JSON Schema ではプロパティを決めないオブジェクトが空になるため、生成では本文を JSON の文字列で受け取る
  GENERATION_SCHEMA = JSON.parse(JSON.generate(SCHEMA), symbolize_names: true).tap do |schema|
    entry = schema.dig(:properties, :items, :items, :properties)
    entry.dig(:request, :properties)[:body] = { type: "string" }
    entry.dig(:expect, :properties)[:body] = { type: "string" }
  end.freeze
  attr_reader :data

  def self.from(conversation, generator: Handbook::OpenRouterClient.new)
    text = generator.generate(prompt: "#{PROMPT}\n会話:\n#{JSON.generate(conversation.messages)}", schema: GENERATION_SCHEMA, schema_name: "verification_items")
    items = from_data(parse_bodies(JSON.parse(text)))
    conversation.store["verification_items"] = items.data
    items
  rescue JSON::ParserError
    raise Handbook::GenerationError, "検証項目を読み取れません"
  end

  def self.stored(conversation)
    data = conversation.context(:verification).store["verification_items"]
    return nil if data.nil?
    new(data)
  end

  def self.from_data(data)
    raise Handbook::GenerationError, "検証項目の形式が不正です" unless JSONSchemer.schema(JSON.parse(JSON.generate(SCHEMA))).valid?(data)
    items = data.fetch("items")
    raise Handbook::GenerationError, "検証項目を読み取れません" if items.empty?
    unless items.all? { |item| METHODS.include?(item.dig("request", "method")) && item.dig("request", "path").start_with?("/") }
      raise Handbook::GenerationError, "検証項目の形式が不正です"
    end
    new(data)
  end
  private_class_method :from_data

  def self.parse_bodies(data)
    Array(data.is_a?(Hash) ? data["items"] : nil).each do |item|
      %w[request expect].each do |key|
        part = item.is_a?(Hash) ? item[key] : nil
        part["body"] = part["body"].strip.empty? ? {} : JSON.parse(part["body"]) if part.is_a?(Hash) && part["body"].is_a?(String)
      end
    end
    data
  end
  private_class_method :parse_bodies

  def initialize(data)
    @data = data
  end

  def to_a
    data.fetch("items").map { |item| Item.new(name: item["name"], request: item["request"], expect: item["expect"]) }
  end
end
