# frozen_string_literal: true
class DevelopmentController < AgentController
  def perceive
    @operation = ApplicationBuild.from(conversation)
    @has_design = !ResourceDesign.recorded(conversation).nil?
    render json: { result: @operation.result, design_available: @has_design }
  end

  def judge
    @finish = @operation.result_available? && (!@operation.succeeded? || @operation.request_complete?)
    render text: if !@has_design
      "生成の対象となる設計がない。"
    elsif @operation.result_available?
      @operation.succeeded? ? "生成は成功した。依頼の到達点に達していれば終了し、残る作業があれば続ける。" : "生成に失敗した。未達を伝えて終了する。"
    else
      "生成をまだ実行していない。ツールに実行を依頼する。"
    end
  end

  def act
    if !@has_design
      render :selected, finish: true
    elsif @operation.result_available?
      render :result, finish: @finish
    else
      render :starting
      render :execute, tool: :bash
    end
  end
end
