# frozen_string_literal: true

require "net/http"
require "uri"

module Handbook
  class JevError < StandardError; end

  class JevClient
    def initialize(api_key: ENV["TYPESAFE_API_KEY"], model: ENV.fetch("JEV_MODEL", "jev-latest"), logger: nil, http: Net::HTTP)
      raise ArgumentError, "TYPESAFE_API_KEY を設定してください" if api_key.to_s.empty?
      @api_key, @model, @logger, @http = api_key, model, logger, http
    end

    def choose(state:, instructions:, criteria:)
      body = { model: @model, state: state, questions: {
        selection: { type: "choice", instructions: instructions, criteria: criteria }
      } }
      uri = URI("https://api.typesafe.ai/v1/systemone")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request.body = JSON.generate(body)
      record("jev_request", body: body)
      response = @http.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.request(request)
      end
      raise JevError, "Jev HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      unless result.is_a?(Hash) && result["answers"].is_a?(Hash)
        raise JevError, "Jev の応答が不正です"
      end
      answer = result.fetch("answers").fetch("selection")
      unless answer.is_a?(Hash) && answer["type"] == "choice" && answer["choice"].is_a?(String) &&
          answer["probabilities"].is_a?(Hash) && answer["confidence"].is_a?(Numeric)
        raise JevError, "Jev の選択結果が不正です"
      end
      record("jev_response", body: result)
      answer
    rescue JSON::ParserError, KeyError, TypeError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
      raise JevError, "Jev 接続または応答のエラー: #{error.class}"
    end

    private

    def record(event, **data)
      @logger&.puts(JSON.generate({ time: Time.now.utc.iso8601(6), event: event }.merge(data)))
    end
  end
end
