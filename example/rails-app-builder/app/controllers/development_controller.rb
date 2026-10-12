# frozen_string_literal: true
class DevelopmentController < AgentController
  def explain
    render json: { result: build.result }
  end

  def check
    render text: "構築するリソース設計が足りない" and return if !build.finished? && build.missing
    render text: "構築済みのアプリケーションが見当たらなかった" and return unless build.finished?
    render text: build.succeeded? ? "構築の成功を確認した" : "構築の失敗を確認した"
  end

  def plan
    return if build.finished? || build.missing
    render text: "構築を開始すると決めた"
  end

  def act
    render :result, finish: !build.succeeded? and return if build.finished?
    render text: "#{build.missing}。", finish: true and return if build.missing
    build.start
    render :execute, tool: :bash
  end

  private

  def build
    @build ||= ApplicationBuild.from(conversation)
  end
end
