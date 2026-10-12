# frozen_string_literal: true
class ResourceDesignController < AgentController
  def explain
    render json: { resource_design: resource_design.data }
  end

  def act
    @resource_design = resource_design
    render :show
  end

  private

  def resource_design
    @resource_design ||= ResourceDesign.from(conversation)
  end
end
