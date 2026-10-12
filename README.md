# Handbook

エージェントの思考を Ruby で記述する、言語システムのフレームワーク。

Handbook は MVC の考え方をエージェント開発へ適用し、「何がわかっていて、何を確かめ、次に何を行うか」を Ruby で作り込めるようにする。判断を誤ったときは、開発者がその箇所を特定して修正・検証し、改善を Ruby のコードとテストとして残せる。

## 現在の状態

試作の段階。

- 確認できていること
  - コーディングエージェント [pi](https://pi.dev/) からの依頼に応じてツール実行を要求し、pi が返す実行結果を受けて処理を続ける
  - サンプルアプリが、利用者の伝えた要求・要件・リソース設計・検証項目から API モードの Rails アプリケーションを構築・起動し、API のリクエストで検証して完了応答まで進む
  - コンテキストの中で、次に呼ぶ思考を Jev が会話と履歴から選び、構築・起動・検証まで進む
  - ライブラリとサンプルアプリの自動テスト 101 件が成功する
- まだできていないこと
  - gem としての配布と、導入・利用文書
  - 会話履歴など実行時の状態の永続化と、再起動後の自動復元
  - 一つ目の依頼で、前提がまだ無いコンテキストが選ばれることがある。このときは不足を伝えてターンを終えるので、利用者がもう一度伝え直す

## 記述例

コンテキストを宣言する。依頼がどのコンテキストに当たるかは、宣言した説明をもとに選ばれる。

```ruby
# example/rails-app-builder/config/contexts.rb
RailsAppBuilder.contexts.draw do
  context :requirements, description: "利用者が伝えた要求を受け付け、利用者へ示す。会話で最初に選ぶ。"
  context :system_requirements, description: "利用者が伝えた要件（機能・品質・制約）を受け付け、利用者へ示す。要求を受け付けたあとに選ぶ。"
  context :resource_design, description: "利用者が伝えたリソース設計を受け付け、利用者へ示す。要件を受け付けたあとに選ぶ。"
  context :development, description: "受け付けたリソース設計から API モードの Rails アプリケーションを構築する。リソース設計を受け付けたあとに選ぶ。"
  context :runtime, description: "構築したアプリケーションを起動する。構築に成功したあとに選ぶ。"
  context :verification, description: "利用者が伝えた検証項目を受け付け、起動したアプリケーションへ API のリクエストを送って検証する。起動に成功したあとに選ぶ。"
end
```

コンテキストごとのコントローラが、explain・ask・check・plan・act の思考を定義する。思考は決まった順に呼ぶ手続きではなく基本の型で、定義した思考のうち次に呼ぶ一つを、思考の選び方が会話とそのコンテキストの履歴から選ぶ。

- `explain`: 会話と履歴から、わかっていることを述べる
- `ask`: 明らかにすべきことを問う
- `check`: 現在地を確かめる
- `plan`: 次に向かう先を決める
- `act`: コマンドを実行するか、利用者へ伝える

act 以外の思考の内容は、思考の名前のタグ（例: `<check>…</check>`）で囲んでコンテキストの履歴に残り、利用者へは act の内容だけが届く。思考は、act が応答するか、いずれかの思考が `finish: true` を指定するまで選び直され、コンテキストを終える。知識と判断はモデルが持ち、応答の表現はビューが担う。

どの思考から呼ばれても同じ判断になるよう、モデルはメモ化した private メソッドから使う。モデルは自分の状態をコンテキストごとのストアへ書き込み、ほかのコンテキストや次のターンはストアから読む。ストアは Jev へは渡さない。

```ruby
# example/rails-app-builder/app/controllers/development_controller.rb
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
```

思考の選び方は、アプリケーションへ渡す。既定の `Handbook::OrderedThoughtSelector` は、まだ選んでいない思考を定義の順に選ぶ。サンプルアプリは `Handbook::JevThoughtSelector` を使い、思考ごとの説明を基準に、次の思考を Jev に選ばせる。

```ruby
# example/rails-app-builder/config.ru
jev = Handbook::JevClient.new(logger: log)
RailsAppBuilder.new(selector: Handbook::JevContextSelector.new(client: jev), thought_selector: Handbook::JevThoughtSelector.new(client: jev))
```

## リポジトリの構成

- `lib/`: Handbook ライブラリの本体
- `test/`: ライブラリのテスト
- `example/rails-app-builder/`: Handbook を使うサンプルアプリ。依頼を受けて Rails アプリケーションを作る

## 動かし方

Ruby 3.2 以上が必要。動作は Ruby 3.4.8 で確認している。

### テスト

リポジトリの root で実行する。

```sh
ruby -I lib -e 'Dir["{test,example/rails-app-builder/test}/*_test.rb"].sort.each { |f| require_relative f }'
```

### サンプルアプリ

サンプルアプリは、コンテキストと思考の選択に Jev を、利用者の伝えた要求・要件・リソース設計・検証項目を構造へ写すのに OpenRouter 経由の言語モデルを使う。次の環境変数が必要。`~/.env` に書いておくと、起動時に読み込まれる。

- `TYPESAFE_API_KEY`: Jev の API キー
- `OPENROUTER_API_KEY`: OpenRouter の API キー

サーバーを起動する。`127.0.0.1:9393` で待ち受ける。

```sh
cd example/rails-app-builder
bundle install
bin/server
```

別の端末から pi を接続する。pi があらかじめ入っている必要がある。インストールの方法は <https://pi.dev/> にある。

```sh
example/rails-app-builder/bin/pi
```

## ライセンス

[MIT License](LICENSE)
