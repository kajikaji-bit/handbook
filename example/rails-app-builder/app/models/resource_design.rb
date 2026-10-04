# frozen_string_literal: true
require "json_schemer"

class ResourceDesign
  Resource = Data.define(:name, :label, :attributes, :operations)
  attr_reader :resources, :data
  PROMPT = <<~PROMPT
    会話で合意した Rails アプリケーションの要求からリソースを設計してください。
    未同意の提案、否定された機能、要求されていない編集・削除・認証・コメントを加えないでください。
    内部の「実装へ進める」などの判断文を機能への同意とは扱わず、利用者の依頼と実際に同意した提案だけを根拠にしてください。
    一覧と詳細は別の操作です。要求されていない操作は補わず、設計に必要な情報が不明なら unresolved に記述してください。
    リソース名は単数形の Ruby クラス名、属性名は snake_case とします。
    アプリケーションの種類に合わせてリソース名・属性・操作を設計してください。
    例えばタスクの登録と一覧なら Task、title:string、completed:boolean、create/index です。
    JSON Schema に従い JSON だけを返してください。不明な要求は推測せず unresolved に記述してください。
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
    unless RailsApplication.recorded(conversation).dig("requirements", "choice") == "defined"
      raise Handbook::GenerationError, "要求の定義を確認できません"
    end
    prompt = "#{PROMPT}\n会話:\n#{JSON.generate(conversation.messages)}"
    text = generator.generate(prompt: prompt, schema: SCHEMA, schema_name: "resource_design")
    design = from_json(text)
    conversation.events.call("resource_designed", prompt: prompt, schema: SCHEMA, model: generator.model, design: design.data)
    design
  end

  def self.recorded(conversation)
    conversation.context(:resource_design).latest(:perceive)
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
