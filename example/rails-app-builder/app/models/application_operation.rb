# frozen_string_literal: true
require "shellwords"
require "rbconfig"

class ApplicationOperation
  APP_ROOT = File.expand_path("../..", __dir__)
  OUTPUT = File.expand_path("../generated-blog", APP_ROOT)
  attr_reader :conversation, :kind

  def self.from(conversation)
    new(conversation)
  end

  def initialize(conversation)
    @conversation = conversation
    @kind = self.class::KIND
    observe if conversation.tool_result && conversation.pending_tool&.fetch("kind") == kind
  end

  def result
    @result
  end

  def result_available?; !result.nil?; end
  def succeeded?; result && result["success"] == true; end
  def request_complete?; RailsApplication.recorded(conversation)["outcome"] == self.class::OUTCOME; end
  def url; result && result["url"]; end

  def command
    raise Handbook::GenerationError, "設計がありません" if ResourceDesign.recorded(conversation).nil?
    if kind != "build" && !conversation.context(:development).latest(:perceive)&.dig("result", "success")
      raise Handbook::GenerationError, "生成が完了していません"
    end
    if kind == "verify" && !conversation.context(:runtime).latest(:perceive)&.dig("result", "success")
      raise Handbook::GenerationError, "起動が完了していません"
    end
    token = SecureRandom.hex(12)
    conversation.pending_tool = { "kind" => kind, "token" => token }
    args = [RbConfig.ruby, File.join(APP_ROOT, "bin", self.class::SCRIPT), "--token", token]
    if kind == "build"
      args += ["--output", OUTPUT, "--design-json", JSON.generate(ResourceDesign.recorded(conversation))]
    else
      args += ["--app", OUTPUT]
      args += kind == "run" ? ["--port", "3000"] : ["--url", conversation.context(:runtime).latest(:perceive).fetch("result").fetch("base_url")]
    end
    Shellwords.join(args)
  end

  private

  def observe
    pending = conversation.pending_tool
    content = conversation.tool_result.fetch("content")
    text = content.is_a?(String) ? content : content.select { |p| p["type"] == "text" }.map { |p| p["text"] }.join("\n")
    line = text.lines.reverse.find { |l| l.start_with?("HANDBOOK_RESULT=") }
    data = line && JSON.parse(line.delete_prefix("HANDBOOK_RESULT="))
    unless data.is_a?(Hash) && data["kind"] == kind && data["token"] == pending["token"] && data["app"] == OUTPUT && [true,false].include?(data["success"])
      data = { "kind" => kind, "app" => OUTPUT, "success" => false, "error" => "ツール結果を照合できませんでした" }
    end
    @result = data
    conversation.pending_tool = nil
  rescue JSON::ParserError, KeyError, TypeError
    @result = { "kind" => kind, "app" => OUTPUT, "success" => false, "error" => "ツール結果が不正です" }
    conversation.pending_tool = nil
  end
end

class ApplicationBuild < ApplicationOperation
  KIND = "build"
  OUTCOME = "build"
  SCRIPT = "build-app"
end
class ApplicationRuntime < ApplicationOperation
  KIND = "run"
  OUTCOME = "run"
  SCRIPT = "start-app"
end
class ApplicationVerification < ApplicationOperation
  KIND = "verify"
  OUTCOME = "verify"
  SCRIPT = "verify-app"
end
