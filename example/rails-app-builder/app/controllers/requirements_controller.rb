# frozen_string_literal: true
class RequirementsController < AgentController
  def explain
    render json: { requirement: requirement.to_h }
  end

  def act
    @requirement = requirement
    render :show
  end

  private

  def requirement
    @requirement ||= Requirement.from(conversation)
  end
end
