# frozen_string_literal: true

class RailsApplication
  CRITERIA = {
    "defined" => "作りたいアプリケーションで扱うデータ、その主要な属性、必要な操作が会話で具体的に定まっている。利用者が具体的な提案に同意した場合も含む。不要と明示した操作は必須にしない。全 CRUD が揃う必要はなく、未要求の編集・削除・認証などを確認するために未定義にしない。例えばタイトルと本文を投稿し一覧と詳細を読むブログは定義済み。",
    "undefined" => "目的だけで扱うデータや主要な属性、必要な操作がまだ決まっていない、または矛盾があり設計に必要な確認が残る。機能を推測して補わない。"
  }.freeze

  def self.from(conversation, judgment: Handbook::JevClient.new)
    new(conversation: conversation, judgment: judgment)
  end

  def initialize(conversation:, judgment:)
    @conversation, @judgment = conversation, judgment
  end

  attr_reader :requirements_judgment, :outcome_judgment

  def self.recorded(conversation)
    conversation.context(:requirements).latest(:judge) || {}
  end

  def requested_outcome
    return @outcome if defined?(@outcome)
    criteria = {
      "design" => "説明や設計が欲しい、またはアプリが欲しいという要望で、生成実行までは明示していない。",
      "build" => "アプリを作って、生成してと依頼し、起動や検証までは頼んでいない。",
      "run" => "アプリを生成し起動するまでを依頼している。",
      "verify" => "アプリを生成・起動し、投稿できることなど動作確認までを明示的に依頼している。"
    }
    answer = @judgment.choose(state: JSON.generate(@conversation.messages), instructions: "利用者が今回求める作業の到達点を選ぶ。内部の提案を実行の依頼と混同せず、指定された範囲だけ選ぶ。", criteria: criteria)
    choice = answer.fetch("choice")
    raise Handbook::JevError, "依頼の到達点が不正です" unless criteria.key?(choice)
    @outcome_judgment = answer
    @outcome = choice
  end

  def requirements_defined?
    return @requirements_defined if defined?(@requirements_defined)

    input = JSON.generate(@conversation.messages)
    instructions = "この会話で実装に必要な要求が合意されているか。提案への同意は要求として読み取り、未同意の提案や否定された機能は補わず判断する。"
    answer = @judgment.choose(state: input, instructions: instructions, criteria: CRITERIA)
    choice = answer.fetch("choice")
    unless CRITERIA.key?(choice)
      raise Handbook::JevError, "要求の判断結果が不正です"
    end
    @requirements_judgment = answer.merge(
      "input" => input, "instructions" => instructions, "criteria" => CRITERIA
    )
    @requirements_defined = choice == "defined"
  end
end
