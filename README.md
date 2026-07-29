# Train Live Map for iOS

関東を走るJR列車の位置推定と運行状況を地図で確認する、SwiftUI製のネイティブiOSアプリです。

- iOS 17以降
- Swift / SwiftUI
- MVVM
- async/await + URLSession
- MapLibre Native for iOS
- Swift Package Manager
- Google Mobile Ads SDK + User Messaging Platform

WebViewは使用していません。既存Web版は仕様の参照元であり、このリポジトリは独立したiOS実装です。

## 主な機能

- APIから取得したJR路線と列車の地図表示
- 路線検索、表示・非表示、お気に入り、お気に入りのみ表示
- 走行中・停車中・遅延・運転見合わせフィルター
- 運行情報、データ取得元、最終更新、次回更新までの表示
- 列車詳細シート
- 路線色、上り・下りの矢印と文字、状態別の顔、遅延・見合わせバッジ
- 線路上へクランプした滑らかな位置補間
- 最終成功データの端末キャッシュと通信失敗時の再試行
- ライト／ダークモード、VoiceOver、Dynamic Type、iPadレイアウト
- UMP同意フロー後に初期化するアダプティブAdMobバナー

列車の表示位置はGPS現在地ではありません。APIの駅間情報などから求めた「位置推定」です。

## セットアップ

必要環境:

- Xcode 16以降
- XcodeGen
- iOS 17以降のSimulator、またはiPhone/iPad

```sh
brew install xcodegen
xcodegen generate
open TrainLiveMap.xcodeproj
```

Xcodeで`TrainLiveMap`スキームを選び、Simulatorで実行してください。Swift Package Managerが次の依存関係を解決します。

- MapLibre 6.28.0
- Google Mobile Ads SDK 13.7.0
- Google User Messaging Platform 3.1.0

アプリのBundle IDは`com.shunsoco.trainlivemap`、表示名は`Train Live Map`です。

## API

既定のBase URLは`Config/Base.xcconfig`で設定しています。

```text
https://train-live-map.vercel.app
```

利用するエンドポイント:

- `GET /api/trains`
- `GET /api/service-status`
- `GET /api/railways`

Base URLは`API_BASE_URL`を変更することで差し替えられます。xcconfig内のURLは`//`がコメントとして扱われないよう、`https:/$()/...`形式で記述しています。

アプリからODPTへ直接アクセスしません。`ODPT_ACCESS_TOKEN`をアプリ、Info.plist、Git履歴へ保存しないでください。トークン管理、モック、フォールバックはVercel側APIの責務です。

`/api/trains`では列車配列に加え、`generatedAt`、`dataUpdatedAt`、`isMock`、`source`、`fallback`、`notice`をデコードします。`/api/railways`の`lines`を地図描画に、`options`の`available`と`coverage`を路線選択に使用します。利用可否をアプリ内の固定値では判定しません。

## 更新、キャッシュ、位置補間

- 列車位置: 7秒
- 運行情報: 30秒
- 路線情報: 起動時
- バックグラウンド: ポーリングと描画補間を停止
- 復帰時: 即時更新

成功レスポンスはApplication Support配下へJSONで保存します。取得失敗時は最後の成功データを残し、「古いデータ」、最終更新時刻、エラー、再試行を表示します。

位置補間は`routeSegment.coordinates`を優先し、なければ路線ポリラインへ投影します。`fromFraction`から`toFraction`への順序を進行方向として扱い、現在の描画位置から区間内を滑らかに移動します。補間は次回更新より前に停止し、データ取得が止まった後に予測移動を続けません。

## AdMobとUMP

[Google Mobile Ads SDKの公式iOS手順](https://developers.google.com/admob/ios/quick-start)に沿ってSPMで導入しています。

Debug構成はGoogle公式テストIDだけを使用します。

- App ID: `ca-app-pub-3940256099942544~1458002511`
- Adaptive Banner: `ca-app-pub-3940256099942544/2435281174`

Release構成ではIDが空のため、広告SDKを初期化せず、広告領域も表示しません。本番IDを設定する場合:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig`へ次を設定します。

```text
ADMOB_APP_ID = ca-app-pub-...
ADMOB_BANNER_UNIT_ID = ca-app-pub-...
```

`Config/Secrets.xcconfig`は`.gitignore`対象です。本物の広告IDやその他の秘密情報をコミットしないでください。対象地域ではUMPの同意情報を更新し、必要なフォームを提示し、広告リクエストが許可された後だけGoogle Mobile Ads SDKを初期化します。

## ビルドとテスト

```sh
xcodebuild \
  -project TrainLiveMap.xcodeproj \
  -scheme TrainLiveMap \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build
```

テスト先はインストール済みSimulatorへ変更してください。

```sh
xcodebuild \
  -project TrainLiveMap.xcodeproj \
  -scheme TrainLiveMap \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

macOSのFile Provider配下で署名用メタデータが生成物へ付く環境では、`-derivedDataPath /tmp/train-live-map-ios-derived-data`を追加してください。

テスト対象:

- API JSONデコード
- 通常・遅延・見合わせの顔
- 上り・下り表示
- 路線検索、表示切替、お気に入り、絞り込み、永続化
- 列車状態フィルター
- ポリライン補間、進行方向、0〜1クランプ、線路上への投影
- データ停止後の補間停止
- API失敗時のキャッシュ
- mock／fallback表示

## 地図の帰属

ベースマップはCARTO VoyagerのOpenStreetMapデータを利用します。MapLibreのロゴと帰属ボタンは非表示にしていません。スタイル内にも`© OpenStreetMap contributors, © CARTO`を設定しています。

## 構成

```text
TrainLiveMap/
├── App/                 アプリ起動と設定
├── Data/                API、キャッシュ、端末設定
├── Domain/              APIモデル、表示ロジック、位置補間
├── Design/              色と共通スタイル
├── Features/
│   ├── Ads/             AdMob、UMP、バナー
│   ├── Filters/         路線検索と設定
│   ├── Main/            メイン画面とViewModel
│   ├── Map/             MapLibre、路線、列車アイコン
│   └── Train/           列車詳細
└── Resources/           App Icon、地図スタイル
```

運用・リリース時の引き継ぎ事項は[HANDOFF.md](HANDOFF.md)を参照してください。
