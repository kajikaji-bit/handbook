# frozen_string_literal: true

module CommandResult
  PREFIX = "HANDBOOK_RESULT="

  def self.receive(conversation, kind:, app:)
    pending = conversation.pending_tool
    return nil unless conversation.tool_result && pending&.fetch("kind") == kind
    conversation.pending_tool = nil
    result = verify(parse(conversation.tool_result.fetch("content")), kind: kind, token: pending["token"], app: app)
    conversation.store["result"] = result
    result
  end

  def self.verify(data, kind:, token:, app:)
    return data if data.is_a?(Hash) && data["kind"] == kind && data["token"] == token && data["app"] == app && [true, false].include?(data["success"])
    { "kind" => kind, "app" => app, "success" => false, "error" => "コマンドの結果を照合できませんでした" }
  end
  private_class_method :verify

  def self.parse(content)
    text = content.is_a?(String) ? content : content.select { |part| part["type"] == "text" }.map { |part| part["text"] }.join("\n")
    line = text.lines.reverse.find { |l| l.start_with?(PREFIX) }
    line && JSON.parse(line.delete_prefix(PREFIX))
  rescue JSON::ParserError
    nil
  end
  private_class_method :parse
end
