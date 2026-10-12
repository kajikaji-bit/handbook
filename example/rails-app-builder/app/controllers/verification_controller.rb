# frozen_string_literal: true
class VerificationController < AgentController
  def explain
    render json: { verification_items: verification_items.data, result: verification.result }
  end

  def check
    render text: "検証の前提の起動が足りない" and return if !verification.finished? && verification.missing
    render text: "検証の記録が見当たらなかった" and return unless verification.finished?
    render text: verification.succeeded? ? "すべての応答が検証項目の期待に合うことを確認した" : "検証の失敗を確認した"
  end

  def plan
    return if verification.finished? || verification.missing
    render text: "検証を開始すると決めた"
  end

  def act
    render :result, finish: true and return if verification.finished?
    render :items
    render text: "#{verification.missing}。", finish: true and return if verification.missing
    verification.start
    render :execute, tool: :bash
  end

  private

  def verification_items
    @verification_items ||= VerificationItems.stored(conversation) || VerificationItems.from(conversation)
  end

  def verification
    verification_items
    @verification ||= ApplicationVerification.from(conversation)
  end
end
