# frozen_string_literal: true
class RuntimeController < AgentController
  def explain
    render json: { result: startup.result }
  end

  def check
    render text: "起動の前提の構築が足りない" and return if !startup.finished? && startup.missing
    render text: "起動済みのアプリケーションが見当たらなかった" and return unless startup.finished?
    render text: startup.succeeded? ? "起動の成功を確認した" : "起動の失敗を確認した"
  end

  def plan
    return if startup.finished? || startup.missing
    render text: "起動を開始すると決めた"
  end

  def act
    render :result, finish: !startup.succeeded? and return if startup.finished?
    render text: "#{startup.missing}。", finish: true and return if startup.missing
    startup.start
    render :execute, tool: :bash
  end

  private

  def startup
    @startup ||= ApplicationStartup.from(conversation)
  end
end
