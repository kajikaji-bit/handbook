# frozen_string_literal: true
require "securerandom"
require "shellwords"
require "rbconfig"

class ApplicationStartup
  KIND = "run"
  APP_ROOT = File.expand_path("../..", __dir__)
  PORT = 3000
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
    finished? && result["success"] == true
  end

  def url
    result&.dig("base_url")
  end

  def missing
    "構築が完了していません" unless built?
  end

  def start
    raise Handbook::GenerationError, missing if missing
    @conversation.pending_tool = { "kind" => KIND, "token" => SecureRandom.hex(12) }
    nil
  end

  def command
    raise Handbook::GenerationError, "起動を開始していません" unless started?
    Shellwords.join([RbConfig.ruby, File.join(APP_ROOT, "bin", "start-app"), "--token", @conversation.pending_tool.fetch("token"),
                     "--app", ApplicationBuild::OUTPUT, "--port", PORT.to_s])
  end

  private

  def built?
    @conversation.context(:development).store.dig("result", "success") == true
  end

  def started?
    @conversation.pending_tool&.fetch("kind") == KIND
  end
end
