# frozen_string_literal: true
require "json_schemer"

class ResourceDesign
  Resource = Data.define(:name, :label, :attributes, :operations)
  attr_reader :resources, :data
  PROMPT = <<~PROMPT
    会話で利用者が伝えたリソース設計を、JSON Schema の構造へ写してください。
    設計を考えたり補ったりせず、利用者が伝えたリソース・属性・操作だけを写してください。
    一覧（index）と詳細（show）は別の操作です。伝えられていない操作は加えないでください。
    リソース名は単数形の Ruby クラス名、属性名は snake_case とします。
    属性の型や操作など、構造へ写すのに必要な情報が伝えられていなければ、推測せず unresolved に記述してください。
    JSON Schema に従い JSON だけを返してください。
  PROMPT
  SCHEMA = {
    type: "object", additionalProperties: false,
    required: %w[resources unresolved],
    properties: {
      resources: {
        type: "array",
        items: {
          type: "object", additionalProperties: false,
          required: %w[name label attributes operations],
          properties: {
            name: { type: "string", pattern: "^[A-Z][A-Za-z0-9]*$" },
            label: { type: "string", minLength: 1 },
            attributes: {
              type: "array",
              items: {
                type: "object", additionalProperties: false,
                required: %w[name type],
                properties: {
                  name: { type: "string", pattern: "^[a-z][a-z0-9_]*$" },
                  type: { type: "string", enum: %w[string text integer bigint float decimal boolean date datetime time] }
                }
              }
            },
            operations: { type: "array", items: { type: "string", enum: %w[create index show update destroy] } }
          }
        }
      },
      unresolved: { type: "array", items: { type: "string" } }
    }
  }.freeze
  def self.from(conversation, generator: Handbook::OpenRouterClient.new)
    prompt = "#{PROMPT}\n会話:\n#{JSON.generate(conversation.messages)}"
    text = generator.generate(prompt: prompt, schema: SCHEMA, schema_name: "resource_design")
    design = from_json(text)
    conversation.events.call("resource_design_received", prompt: prompt, schema: SCHEMA, model: generator.model, design: design.data)
    conversation.store["resource_design"] = design.data
    design
  end

  def self.stored(conversation)
    data = conversation.context(:resource_design).store["resource_design"]
    return nil if data.nil?
    new(data)
  end

  def self.from_json(json)
    data = JSON.parse(json)
    schema = JSON.parse(JSON.generate(SCHEMA))
    raise Handbook::GenerationError, "リソース設計の形式が不正です" unless JSONSchemer.schema(schema).valid?(data)
    raise Handbook::GenerationError, "リソース設計が未確定です" unless data.fetch("unresolved").empty?
    resources = data.fetch("resources")
    reserved = %w[id type created_at updated_at class module def end send save destroy attributes]
    if resources.empty? || resources.map { |r| r["name"] }.uniq.size != resources.size
      raise Handbook::GenerationError, "リソース名が空または重複しています"
    end
    resources.each do |r|
      names = r["attributes"].map { |a| a["name"] }
      if %w[ApplicationRecord ApplicationController Object Kernel].include?(r["name"]) || names.empty? || names.uniq.size != names.size || !(names & reserved).empty? || r["operations"].empty? || r["operations"].uniq != r["operations"]
        raise Handbook::GenerationError, "リソース設計の名前または操作が不正です"
      end
    end
    new(data)
  rescue JSON::ParserError
    raise Handbook::GenerationError, "リソース設計の JSON が不正です"
  end

  def initialize(data)
    @data = data
    @resources = data.fetch("resources").map { |r| Resource.new(name: r["name"], label: r["label"], attributes: r["attributes"], operations: r["operations"]) }
  end
end
