# frozen_string_literal: true
class SystemRequirementsController < AgentController
  def explain
    render json: { system_requirement: system_requirement.to_h }
  end

  def act
    @system_requirement = system_requirement
    render :show
  end

  private

  def system_requirement
    @system_requirement ||= SystemRequirement.from(conversation)
  end
end
