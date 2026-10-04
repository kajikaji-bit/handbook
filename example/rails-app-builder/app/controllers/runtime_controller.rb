# frozen_string_literal: true
class RuntimeController < AgentController
  def perceive
    @operation = ApplicationRuntime.from(conversation)
    @has_design = !ResourceDesign.recorded(conversation).nil?
    render json: { result: @operation.result, design_available: @has_design }
  end

  def judge
    @finish = @operation.result_available? && (!@operation.succeeded? || @operation.request_complete?)
    render text: if !@has_design
      "起動の対象となる設計がない。"
    elsif @operation.result_available?
      @operation.succeeded? ? "起動は成功した。依頼の到達点に達していれば終了し、残る作業があれば続ける。" : "起動に失敗した。未達を伝えて終了する。"
    else
      "起動をまだ実行していない。ツールに実行を依頼する。"
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
