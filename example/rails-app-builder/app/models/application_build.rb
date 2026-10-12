# frozen_string_literal: true
require "securerandom"
require "shellwords"
require "rbconfig"

class ApplicationBuild
  KIND = "build"
  APP_ROOT = File.expand_path("../..", __dir__)
  OUTPUT = File.expand_path("../generated-blog", APP_ROOT)
  attr_reader :result

  def self.from(conversation)
    new(conversation, CommandResult.receive(conversation, kind: KIND, app: OUTPUT))
  end

  def initialize(conversation, result)
    @conversation = conversation
    @result = result
  end

  def finished?
    !result.nil?
  end

  def succeeded?
    finished? && result["success"] == true
  end

  def missing
    "構築するリソース設計がありません" if ResourceDesign.stored(@conversation).nil?
  end

  def start
    raise Handbook::GenerationError, missing if missing
    @conversation.pending_tool = { "kind" => KIND, "token" => SecureRandom.hex(12) }
    nil
  end

  def command
    raise Handbook::GenerationError, "構築を開始していません" unless started?
    Shellwords.join([RbConfig.ruby, File.join(APP_ROOT, "bin", "build-app"), "--token", @conversation.pending_tool.fetch("token"),
                     "--output", OUTPUT, "--design-json", JSON.generate(ResourceDesign.stored(@conversation).data)])
  end

  private

  def started?
    @conversation.pending_tool&.fetch("kind") == KIND
  end
end
