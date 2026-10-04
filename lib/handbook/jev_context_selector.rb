# frozen_string_literal: true

module Handbook
  class JevContextSelector
    def initialize(client: JevClient.new)
      @client = client
    end

    def call(contexts:, conversation:)
      criteria = contexts.definitions.to_h { |name, definition| [name.to_s, definition.fetch(:description)] }
      raise ArgumentError, "コンテキストがありません" if criteria.empty?
      answer = @client.choose(
        state: JSON.generate(conversation.selection_state),
        instructions: "利用者の最新の依頼と会話、内部の判断、実行済みの処理から、次に必要な文脈を候補の説明に基づいて一つ選ぶ。完了した判断を繰り返さず、未実行の必要な処理へ進む。",
        criteria: criteria
      )
      choice = answer.fetch("choice")
      raise JevError, "Jev が未知のコンテキストを返しました" unless criteria.key?(choice)
      conversation.context_selection = answer
      contexts.definitions.keys.find { |name| name.to_s == choice }
    end
  end
end
