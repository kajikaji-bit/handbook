# frozen_string_literal: true

class ConnectionController < AgentController
  def act
    render :connected, finish: true
  end
end
