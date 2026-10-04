# frozen_string_literal: true

class AgentController < Handbook::Controller
  def act
    render :selected, finish: true
  end
end
