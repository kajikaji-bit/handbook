# frozen_string_literal: true

require "net/http"

module Handbook
  class GenerationError < StandardError; end

  class OpenRouterClient
    attr_reader :model

    def initialize(api_key: ENV["OPENROUTER_API_KEY"], model: ENV.fetch("OPENROUTER_MODEL", "google/gemini-3.1-flash-lite"), http: Net::HTTP)
      raise GenerationError, "OPENROUTER_API_KEY を設定してください" if api_key.to_s.empty?
      @api_key, @model, @http = api_key, model, http
    end

    def generate(prompt:, schema: nil, schema_name: "result")
      uri = URI("https://openrouter.ai/api/v1/chat/completions")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      body = { model: model, stream: false, messages: [{ role: "user", content: prompt }] }
      if schema
        body[:response_format] = { type: "json_schema", json_schema: { name: schema_name, strict: true, schema: schema } }
        body[:provider] = { require_parameters: true }
      end
      request.body = JSON.generate(body)
      response = @http.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) { |http| http.request(request) }
      raise GenerationError, "文章生成の通信に失敗しました" unless response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      choice = result.fetch("choices").fetch(0)
      text = choice.fetch("message").fetch("content")
      unless choice["finish_reason"] == "stop" && text.is_a?(String) && !text.strip.empty?
        raise GenerationError, "文章生成の応答が不正です"
      end
      text
    rescue JSON::ParserError, KeyError, IndexError, TypeError, NoMethodError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise GenerationError, "文章生成の接続または応答に失敗しました"
    end
  end
end
