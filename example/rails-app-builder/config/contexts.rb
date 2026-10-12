# frozen_string_literal: true
RailsAppBuilder.contexts.draw do
  context :requirements, description: "利用者が伝えた要求を受け付け、利用者へ示す。会話で最初に選ぶ。"
  context :system_requirements, description: "利用者が伝えた要件（機能・品質・制約）を受け付け、利用者へ示す。要求を受け付けたあとに選ぶ。"
  context :resource_design, description: "利用者が伝えたリソース設計を受け付け、利用者へ示す。要件を受け付けたあとに選ぶ。"
  context :development, description: "受け付けたリソース設計から API モードの Rails アプリケーションを構築する。リソース設計を受け付けたあとに選ぶ。"
  context :runtime, description: "構築したアプリケーションを起動する。構築に成功したあとに選ぶ。"
  context :verification, description: "利用者が伝えた検証項目を受け付け、起動したアプリケーションへ API のリクエストを送って検証する。起動に成功したあとに選ぶ。"
end
