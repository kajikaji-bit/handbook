# Handbook

知覚と判断を Ruby で記述する、言語システムのフレームワークです。

Handbook は MVC の考え方をエージェント開発へ適用し、「何を捉え、どう判断し、何を行うか」を Ruby で作り込めるようにします。判断を誤ったときは、開発者がその箇所を特定して修正・検証し、改善を Ruby のコードとテストとして残せます。

## 現在の状態

試作の段階です。

- 確認できていること
  - コーディングエージェント [pi](https://pi.dev/) からの依頼に応じてツール実行を要求し、pi が返す実行結果を受けて処理を続ける
  - サンプルアプリがブログを生成・起動し、画面からの記事投稿、一覧と詳細の表示、完了応答まで進む
  - ライブラリとサンプルアプリの自動テスト 36 件が成功する
- まだできていないこと
  - gem としての配布と、導入・利用文書
  - 会話履歴など実行時の状態の永続化と、再起動後の自動復元
  - ブログ以外のアプリケーションでの一連の動作の確認

## 記述例

文脈を宣言します。依頼がどの文脈に当たるかは、宣言した説明をもとに選ばれます。

```ruby
# example/rails-app-builder/config/contexts.rb
RailsAppBuilder.contexts.draw do
  context :requirements, description: "Web アプリケーションの要望、制約、必要な機能を理解し、要求と作業の到達点を判断する。"
  context :resource_design, description: "合意した要求からリソースと属性、必要な操作を設計する。"
  context :development, description: "リソース設計をもとに Rails アプリケーションのコードを生成する。"
  context :runtime, description: "生成したアプリケーションを起動し、稼働状態を確認する。"
  context :verification, description: "起動したアプリケーションが要求どおり動くか画面で確認する。"
end
```

文脈ごとのコントローラが、知覚 (`perceive`)・判断 (`judge`)・行動 (`act`) をつなぎます。知識と判断はモデルが持ち、応答の表現はビューが担います。

```ruby
# example/rails-app-builder/app/controllers/requirements_controller.rb
class RequirementsController < AgentController
  def perceive
    @application = RailsApplication.from(conversation)
    render text: conversation.user_message
  end

  def judge
    @defined = @application.requirements_defined?
    @outcome = @application.requested_outcome if @defined
    render json: { requirements: @application.requirements_judgment, outcome: @outcome, outcome_judgment: @application.outcome_judgment }
  end

  def act
    if @defined
      render :ready
    else
      @conversations = conversation.messages
      render :ask_features, generate: true, finish: true
    end
  end
end
```

## リポジトリの構成

- `lib/`: Handbook ライブラリの本体
- `test/`: ライブラリのテスト
- `example/rails-app-builder/`: Handbook を使うサンプルアプリ。依頼を受けて Rails アプリケーションを作る

## 動かし方

Ruby 3.2 以上が必要です。動作は Ruby 3.4.8 で確認しています。

### テスト

リポジトリの root で実行します。

```sh
ruby -I lib -e 'Dir["{test,example/rails-app-builder/test}/*_test.rb"].sort.each { |f| require_relative f }'
```

### サンプルアプリ

サンプルアプリは、文脈の選択と判断に Jev を、質問と設計の生成に OpenRouter 経由の言語モデルを使います。次の環境変数が必要です。`~/.env` に書いておくと、起動時に読み込まれます。

- `TYPESAFE_API_KEY`: Jev の API キー
- `OPENROUTER_API_KEY`: OpenRouter の API キー

サーバーを起動します。`127.0.0.1:9393` で待ち受けます。

```sh
cd example/rails-app-builder
bundle install
bin/server
```

別の端末から pi を接続します。pi があらかじめ入っている必要があります。インストールの方法は <https://pi.dev/> にあります。

```sh
example/rails-app-builder/bin/pi
```

依頼からブログの完成までを再現する手順は、これから文書として整えます。

## ライセンス

[MIT License](LICENSE)
