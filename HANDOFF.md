# Train Live Map iOS 引き継ぎ

## 現在の状態

`Train Live Map / JR東日本・関東版（非公式）`のネイティブiOS実装です。
SwiftUI、MapLibre、4種のVercel API、端末キャッシュ、路線設定、列車補間、
利用者投稿、APNsクライアント、AdMob／UMP、Unit／UI Testまで実装済みです。

既存Web版`shunsoco-stack/train-live-map`は型とAPI仕様の確認にだけ使用し、変更して
いません。iOSコードは別リポジトリ`shunsoco-stack/train-live-map-ios`だけで
管理します。`baobao-privacy-policy`にも変更を加えません。

## 製品情報

| 項目 | 値 |
| --- | --- |
| アプリ名 | Train Live Map |
| エディション | JR東日本・関東版（非公式） |
| App Store掲載名候補 | Train Live Map - JR東日本 関東版 |
| Bundle ID | `com.shunsoco.trainlivemap` |
| Deployment Target | iOS 17.0 |
| Marketing Version | 1.1.0 |
| Build Number | 1 |
| 問い合わせ | `train-live-map-support@gmail.com` |
| API Base URL | `https://train-live-map.vercel.app` |

Apple Developer Team、署名、Release用外部IDはリポジトリへ固定していません。

## プロジェクト管理

`project.yml`がXcodeプロジェクト設定の正本です。ターゲット、Build Settings、
Swift Packageを変えた場合:

```sh
xcodegen generate
git add project.yml TrainLiveMap.xcodeproj
```

パッケージは次のバージョンへ固定しています。

- MapLibre Native 6.28.0
- Google Mobile Ads 13.7.0
- Google User Messaging Platform 3.1.0

## 実装責務

- `TrainLiveMapApp`: 依存生成、scene phase、ポーリング開始／停止
- `AppConfiguration`: Info.plistへ展開されたxcconfig値の正規化
- `MainView`: メイン地図、コンパクトパネル、各Sheetへの導線
- `MainViewModel`: キャッシュ復元、4 API更新、ポーリング、表示用絞り込み
- `TrainRepository`: UIとAPI／キャッシュを分離
- `URLSessionTrainAPIService`: Vercel APIのGET／POST、HTTP／JSON検証
- `FileResponseCache`: 4レスポンスのApplication Support保存
- `UserPreferences`: 表示、お気に入り、通知対象、Reporter ID、投稿時刻
- `RailwaySelectionLogic`: APIカテゴリごとの初期1路線、選択中だけの運行情報
- `ServiceStatusLogic`: ODPT文面優先、2分鮮度、列車遅延による補完と重大判定
- `CommunityReportLogic`: 30分集計、中央値、重大度tie-break、通知閾値判定
- `TrainMotionEngine`: routeSegment、線路投影、区間内補間、Reduce Motion
- `MapLibreTrainMap`: 路線casing、ラベル、古いlayer削除、自動viewport
- `TrainIconView`: 路線色、上下文字、顔、涙、遅延／見合わせ表示
- `NotificationManager`: 権限、APNs token、購読同期、通知deep link
- `AdManager`: UMP同意、SDK初期化、プライバシー設定

依存方向は`View → ViewModel → Repository → APIClient → Web API`です。

## API

アプリが直接呼ぶのは次だけです。

- `GET /api/trains`
- `GET /api/service-status`
- `GET /api/railways`
- `GET /api/community-reports`
- `POST /api/community-reports`

ODPTへ直接アクセスするコードを追加しないでください。`ODPT_ACCESS_TOKEN`を
アプリ、Info.plist、xcconfig、ログ、Git履歴へ入れないでください。

2026-07-30の本番API確認:

- trains: 最終確認時251件、`source=odpt`、`isMock=false`、`fallback=false`
- railways: 36形状、41選択肢、40選択可能、7カテゴリ
- service-status: 36路線、`source=odpt`、`fallback=false`
- community-reports: 30分窓、`votingEnabled=true`、`persistent=true`

本番APIの内容は変化するため、固定件数をアプリロジックへ使わないでください。

### APIモデル更新時

次を同時に確認します。

1. 既存Web版の`src/types`と`src/app/api`
2. 本番レスポンス
3. `TrainLiveMap/Domain`
4. `TrainLiveMapTests/Fixtures`
5. `APIJSONDecodingTests`

本番`/api/community-reports`は稼働していますが、確認時点のWeb参照リポジトリには
同ルートのソースが含まれていませんでした。バックエンド変更時はVercelへ実際に
デプロイされているソースとの一致を先に確認してください。

## 対象路線と形状の注意

路線選択肢は`options.available`と`coverage`を優先します。2026-07-30時点の
選択対象はREADME記載の40路線です。上野東京ライン、相模線、鶴見線、八高線、
南武支線は選択対象外です。

同時点で、APIは信越本線、烏山線、日光線、両毛線、小海線、水郡線、水戸線を
選択可能として返しますが、`lines`には同IDの全線形状がありません。この場合、
列車の`routeSegment`または座標を利用できても、全線ポリラインは描画できません。
推測形状をiOS側へ固定追加せず、バックエンドの`lines`拡充を優先してください。

逆に`lines`へ相模線、鶴見線、八高線の形状が含まれても、利用可能な`options`が
ないため選択画面へ出しません。

## 更新とキャッシュ

| データ | 間隔 |
| --- | --- |
| 列車 | 7秒 |
| 公式運行情報 | 30秒 |
| 路線 | 起動時 |
| みんなの運行情報 | 20秒 |

バックグラウンドでは全ポーリングと補間を止め、復帰時に即時更新します。

Application Support:

```text
TrainLiveMap/Cache/
├── trains.json
├── service-status.json
├── railways.json
└── community-reports.json
```

通信失敗時はキャッシュを消さず、古いデータの表示、更新時刻、エラー、再試行を
維持します。キャッシュ保存失敗は有効なネットワークデータを無効化しません。

## UserDefaults

- `train-live-map.visible-line-ids`
- `train-live-map.favorite-line-ids`
- `train-live-map.notification-line-ids`
- `train-live-map.favorites-only`
- `train-live-map.visibility-initialized`
- `train-live-map.community-reporter-id`
- `train-live-map.community-submission-dates`

初回だけAPIカテゴリごとの利用可能な先頭1路線を選び、以後は保存値を復元します。
APIから消えたIDは`reconcile`で表示／お気に入り／通知対象から除外します。

Reporter IDはランダムUUID由来で、氏名、メール、位置情報などの個人情報を保存しません。

## 列車位置と表示

表示位置はGPS現在地と断定しません。画面には
`ODPTライブ（位置は駅間推定）`を表示し、詳細で`actual`／`estimated`／`mock`を
区別します。

位置更新の優先順位:

1. `routeSegment.coordinates`
2. `routeSegment.fromFraction`／`toFraction` + 路線ポリライン
3. APIの緯度経度を路線ポリラインへ投影

停止中、見合わせ中、バックグラウンド、Reduce Motion時は補間しません。
区間終端や次駅を越えて外挿せず、次スナップショットが来る前に停止します。

## みんなの運行情報

クライアント側でも次を検証します。

- 遅延分数は1〜120
- 30分以内だけを集計
- 遅延分数は中央値
- 同数は`運転見合わせ > 遅延 > 平常`
- APIの`cooldownSeconds`中は同一路線への再投稿を止める

バックエンド側の入力検証、Reporter単位レート制限、永続化を必ず維持してください。
公式情報と利用者投稿はUIでもモデルでも分離しています。

## APNsバックエンドの残作業

iOSクライアント側は完成していますが、現行WebバックエンドにはAPNs端末登録／
配信処理がありません。`APNS_REGISTRATION_URL`には次を受けるHTTPS POSTを用意します。

```json
{
  "deviceToken": "<hex APNs token>",
  "lineIds": ["tokaido", "yamanote"],
  "platform": "ios",
  "bundleId": "com.shunsoco.trainlivemap"
}
```

必要なサーバー責務:

- tokenと購読路線のupsert／解除／失効token削除
- APNs provider tokenまたは証明書の安全な保管
- 直近5分、異なるReporterの最新票だけを1票として集計
- 見合わせ3件以上かつ60%以上
- 前5分の見合わせ票が多い場合は2倍以上（最低でも前窓+2件）
- 路線別クールダウンと通知重複防止
- お気に入り／通知登録路線だけへ送信
- payloadの`userInfo.lineId`
- 「可能性」「利用者からの報告」「公式情報をご確認ください」の文言

APNs key、Team ID、Key IDはGitへ保存せず、Vercel等のSecretへ設定します。

## AdMob／UMP

DebugはGoogle公式テストIDだけを使用します。Release用:

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

設定項目:

- `ADMOB_APP_ID`
- `ADMOB_BANNER_UNIT_ID`
- 任意の`APNS_REGISTRATION_URL`

`Config/Base.xcconfig`末尾で任意Secretsを読み、その後Debugが公式テストIDを
上書きするため、開発ビルドへ本物の広告IDが混入しません。Release IDが空なら
SDKもバナー領域も無効です。

公開前にAdMob管理画面のUMPメッセージ、プライバシーオプション、
最新SKAdNetwork一覧を確認してください。

## 検証結果

最終コミット前のSimulator検証:

- Debug Simulator署名付きbuild-for-testing: 成功
- Release Simulator build: 成功
- Release実機向け署名なしコンパイル: 成功
- Unit Test: 42件成功、失敗0（運行情報補完11件を含む）
- 標準iPhone UI Test: 3件成功、失敗0
- iPhone SE相当: 主要UI／VoiceOverスモーク成功、目視確認済み
- iPhone Pro Max相当: 最大Dynamic Type／ダーク／通知UI成功
- iPad Pro 11-inch相当: 主要UI／VoiceOverスモーク成功、目視確認済み
- 本番APIモードのSimulator起動: 成功、ODPT列車と7カテゴリ初期選択を描画
- App Icon: 全宣言サイズ一致、アルファなし
- M PLUS Rounded: 3ウェイトをbundleから正常読込

Unit Testの範囲:

- 4 APIレスポンスのCodable
- actual／estimated／mock、fallback
- 路線色、初期選択、検索、表示、お気に入り、通知対象、永続化
- 表示路線だけの公式運行情報
- 運転再開／現在見合わせの文脈分類、古い列車を除外した遅延補完
- 全状態フィルター
- 上下方向、顔、涙、遅延吹き出し、VoiceOver文言
- 補間、0〜1クランプ、線路投影、停止、Reduce Motion
- API失敗時のキャッシュ維持
- 30分投稿集計、中央値、通知閾値

## 既知の制約

- ODPT列車位置は駅間推定で、実際のGPS走行位置とは異なる場合があります。
- `fromStation`／`toStation`がAPI未提供の場合、詳細は駅名なしの駅間推定表示です。
- 速度や停車開始時刻はAPI提供時だけ表示精度を保証できます。値を推測しません。
- 一部の選択可能路線はAPIに全線形状がありません。
- Webバックエンド、ODPT、CARTO、OpenStreetMap、Google広告の可用性に依存します。
- APNs端末登録／配信バックエンドは未提供です。
- バックグラウンド更新と位置情報権限は意図的に実装していません。
- Release用AdMob ID、Apple署名、APNs外部設定は未設定です。

## App Store提出前チェックリスト

### Apple／署名

- Apple Developer Teamを設定
- Bundle ID `com.shunsoco.trainlivemap`を登録
- Push Notifications capabilityとAPNs key／証明書を設定
- Distribution certificate／profileまたはXcode Cloudを設定
- Release Archiveと実機で起動、投稿、通知deep linkを確認

### バックエンド／外部ID

- APNs端末登録URLと送信workerを実装
- `APNS_REGISTRATION_URL`をReleaseへ注入
- AdMob App ID／Adaptive Banner Unit IDをReleaseへ注入
- UMPメッセージを必要地域向けに公開
- 本番APIの4エンドポイントとCORS／rate limitを再確認

### App Store Connect

- 掲載名、サブタイトル、説明、キーワード、カテゴリを確定
- サポートURL、マーケティングURL、Train Live Map用プライバシーポリシーURLを用意
- iPhone各サイズとiPadのスクリーンショットを作成
- App Privacy回答でAPI投稿、匿名ID、広告SDKの取扱いを正確に申告
- 年齢区分、輸出コンプライアンス、広告識別子の回答
- 「JR東日本・関東版（非公式）」と位置推定の説明を審査メモにも記載
- JR東日本の公式ロゴ／車両デザインを使用していないことを確認

### データ利用条件

- [ODPT開発者サイト](https://developer.odpt.org/)と
  [データカタログ](https://ckan.odpt.org/)でチャレンジ2026条件を再確認
- OpenStreetMap／CARTOの帰属が表示されることを確認
- アプリ内「このアプリについて」の非公式表記、問い合わせ、クレジットを確認

## 再検証コマンド

```sh
xcodegen generate

xcodebuild -project TrainLiveMap.xcodeproj -scheme TrainLiveMap \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project TrainLiveMap.xcodeproj -scheme TrainLiveMap \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project TrainLiveMap.xcodeproj -scheme TrainLiveMap \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

macOSのファイル調停でプロジェクト読込が遅い環境では、検証専用コピーまたは
`-derivedDataPath /tmp/train-live-map-ios-derived-data`を使用してください。
