# frozen_string_literal: true

class ToolCheckController < AgentController
  def act
    if conversation.tool_result
      render :completed, finish: true
    else
      render :execute, tool: :bash
    end
  end
end
