# frozen_string_literal: true
require "securerandom"
require "shellwords"
require "rbconfig"

class ApplicationVerification
  KIND = "verify"
  APP_ROOT = File.expand_path("../..", __dir__)
  attr_reader :result

  def self.from(conversation)
    new(conversation, CommandResult.receive(conversation, kind: KIND, app: ApplicationBuild::OUTPUT))
  end

  def initialize(conversation, result)
    @conversation = conversation
    @result = result
  end

  def finished?
    !result.nil?
  end

  def succeeded?
    finished? && result["success"] == true && item_results.any? && item_results.all? { |item| item["passed"] == true }
  end

  def item_results
    result&.fetch("items", nil) || []
  end

  def missing
    return "起動が完了していません" if url.nil?
    "検証項目がありません" if VerificationItems.stored(@conversation).nil?
  end

  def start
    raise Handbook::GenerationError, missing if missing
    @conversation.pending_tool = { "kind" => KIND, "token" => SecureRandom.hex(12) }
    nil
  end

  def command
    raise Handbook::GenerationError, "検証を開始していません" unless started?
    Shellwords.join([RbConfig.ruby, File.join(APP_ROOT, "bin", "verify-app"), "--token", @conversation.pending_tool.fetch("token"),
                     "--app", ApplicationBuild::OUTPUT, "--url", url, "--items-json", JSON.generate(VerificationItems.stored(@conversation).data.fetch("items"))])
  end

  private

  def url
    startup = @conversation.context(:runtime).store["result"]
    return nil unless startup&.fetch("success", false) == true
    startup["base_url"]
  end

  def started?
    @conversation.pending_tool&.fetch("kind") == KIND
  end
end
