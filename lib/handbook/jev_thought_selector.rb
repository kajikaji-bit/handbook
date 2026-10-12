# frozen_string_literal: true

module Handbook
  class JevThoughtSelector
    INSTRUCTIONS = "このコンテキストで次に呼ぶ思考を一つ選ぶ。messages は会話とこのコンテキストの履歴で、act 以外の思考の記録は思考の名前のタグで囲まれている。chosen はこのターンですでに選んだ思考の並びで、選んでも記録が増えなかった思考は、いまはすることが無い。利用者へ伝えるかコマンドを実行してよいとわかったら act を選ぶ"
    DESCRIPTIONS = {
      explain: "このコンテキストが受け取ったものと、会話と履歴からわかっていることを述べる",
      ask: "進めるために、利用者に明らかにしてもらうことを書き出す",
      check: "前提がそろっているか、結果が出ているかを確かめ、足りないものを書き出す",
      plan: "前提がそろっているとわかったうえで、次に何をするかを決める",
      act: "コマンドを実行するか、結果や足りないものを利用者へ伝えて、このコンテキストを終える"
    }.freeze

    def initialize(client: JevClient.new)
      @client = client
    end

    def call(thoughts:, conversation:, chosen:)
      criteria = thoughts.to_h { |thought| [thought.to_s, DESCRIPTIONS.fetch(thought)] }
      answer = @client.choose(
        state: JSON.generate(messages: conversation.messages, chosen: chosen.map(&:to_s)),
        instructions: INSTRUCTIONS,
        criteria: criteria
      )
      choice = answer.fetch("choice")
      raise JevError, "Jev が未知の思考を返しました" unless criteria.key?(choice)
      choice.to_sym
    end
  end
end
