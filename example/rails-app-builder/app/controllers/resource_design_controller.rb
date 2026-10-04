# frozen_string_literal: true
class ResourceDesignController < AgentController
  def perceive
    @resource_design = ResourceDesign.from(conversation)
    render json: @resource_design.data
  end

  def judge
    @finish = RailsApplication.recorded(conversation).fetch("outcome", "design") == "design"
    render text: @finish ? "依頼された設計ができた。設計を表示して終了する。" : "要求に沿った設計ができた。設計を表示し、アプリケーションの生成へ進める。"
  end

  def act
    render :show, finish: @finish
  end
end
