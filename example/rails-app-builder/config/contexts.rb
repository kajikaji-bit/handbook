# frozen_string_literal: true
RailsAppBuilder.contexts.draw do
  context :requirements, description: "Web アプリケーションの要望、制約、必要な機能を理解し、要求と作業の到達点を判断する。"
  context :resource_design, description: "合意した要求からリソースと属性、必要な操作を設計する。"
  context :development, description: "リソース設計をもとに Rails アプリケーションのコードを生成する。"
  context :runtime, description: "生成したアプリケーションを起動し、稼働状態を確認する。"
  context :verification, description: "起動したアプリケーションが要求どおり動くか画面で確認する。"
end
