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
- `UserPreferences`: 表示、お気に入り、通知対象、投稿時刻
- Reporter IDストア: ランダム端末IDのKeychain保存と旧UserDefaults値の安全な移行
- `RailwaySelectionLogic`: APIカテゴリごとの初期1路線、選択中だけの運行情報
- `ServiceStatusLogic`: ODPT文面優先、2分鮮度、列車遅延による補完と重大判定
- `TrainNumberSearchLogic`: 表示中の最新列車だけを対象にした番号前方一致検索
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

`API_BASE_URL`はhostを持つ`https` URLだけを許可します。`http`へフォールバック
したり、ATS例外を追加したりしないでください。Community ReportのPOSTは
`Content-Type: application/json`と`X-Community-Reporter`が必須です。Reporter IDは
Keychainのランダム値を使用し、ヘッダーや本文をログへ出力しません。Keychain保存を
確認できない場合は投稿をfail-closedで送信しません。

`GET /api/trains`と`GET /api/service-status`には選択中の
`/api/railways.options[].id`を昇順・重複なしで連結し、
`?lines=tokaido,yamanote`として渡します。0路線時は要求を送りません。IDは
`^[a-z0-9-]{1,64}$`、最大44路線、値全体1,024文字以内です。
`serviceStatuses`が存在するときは空配列も正式な結果であり、legacyの単数
`serviceStatus`へ戻してはいけません。

起動時は、保存済み`/api/railways`キャッシュをUI復元に使いつつ、列車・運行情報の
選択路線ポーリングを開始する前にカタログを1回再取得します。成功時はサーバーの最新
`options`へ選択を整合し、失敗時はキャッシュを表示用フォールバックとして維持します。
キャッシュもない場合は選択路線ポーリングを開始せず、単一の空状態から手動再試行できます。

Webバックエンドの`400`、`403`、`413`、`415`、`429`、`503`は個別に扱います。
路線APIの`400`は選択IDが変わるまで再送せず、`429`は`Retry-After`
（delta-secondsまたはHTTP-date）まで、`503`は`Retry-After`または次の通常周期まで
再送しません。処理中の同一要求、連打、再帰的な自動リトライは禁止です。

`ODPT_ACCESS_TOKEN`、Redis URL／token、`VAPID_PRIVATE_KEY`、
`REPORTER_HASH_SALT`、legacy fallbackの`COMMUNITY_REPORT_HMAC_SECRET`は
サーバー専用です。クライアント設定、バイナリ、ログ、Gitへ含めません。

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

2026-08-01時点のWeb版では、`/api/community-reports`にJSON限定、16KiB上限、
Reporter／接続元単位の回数制限が実装されています。エラー本文は`{ "error": "..." }`、
`429`の`Retry-After`は秒数です。バックエンド変更時はWeb版`origin/main`とVercelへ
実際にデプロイされているソースの一致を先に確認してください。

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
| 列車 | 10秒 |
| 公式運行情報 | 10秒 |
| 路線 | 起動時 |
| みんなの運行情報 | 10秒 |

バックグラウンドでは全ポーリングと補間を止め、復帰時に即時更新します。

Application Support:

```text
TrainLiveMap/Cache/
├── trains.json
├── service-status.json
├── railways.json
└── community-reports.json
```

通信失敗時はキャッシュを消さず、更新時刻、エラー、再試行を維持します。オンライン中の
一時的なAPI失敗では最後の成功位置を「古いデータ」と明示して、地図、列車番号検索、
詳細に保持します。オフライン検知時だけ過去座標を現在位置として扱わず列車マーカーと
検索／詳細を即座に隠し、復帰後の成功レスポンスで再表示します。
停止時間表示だけを1秒ごとに局所更新し、画面全体は1秒周期で更新しません。
キャッシュ保存失敗は有効なネットワークデータを無効化しません。

## UserDefaults

- `train-live-map.visible-line-ids`
- `train-live-map.favorite-line-ids`
- `train-live-map.notification-line-ids`
- `train-live-map.favorites-only`
- `train-live-map.visibility-initialized`
- `train-live-map.community-submission-dates`

初回だけAPIカテゴリごとの利用可能な先頭1路線を選び、以後は保存値を復元します。
APIから消えたIDは`reconcile`で表示／お気に入り／通知対象から除外します。

Reporter IDは`^[A-Za-z0-9_-]{12,100}$`に適合するランダムUUID由来で、Keychainへ保存します。旧版の
`train-live-map.community-reporter-id`がUserDefaultsにあれば、形式を検証して
Keychainへ一度だけ移行し、旧値を削除します。氏名、メール、位置情報などの個人情報は
保存しません。

## 列車位置と表示

表示位置はGPS現在地と断定しません。画面には
`ODPTライブ（位置は駅間推定）`を表示し、詳細で`actual`／`estimated`／`mock`を
区別します。

列車番号検索は表示中かつ最新の列車だけを対象に、trim済み・大文字小文字を無視した
前方一致で最大5件を返します。選択時は状態フィルターを解除して対象markerを表示し、
地図を最低zoom 12以上へ移動して詳細Sheetを開きます。凡例では列車状態、上り／下り、
実データ／推定／モックと、GPSの正確な位置ではないことを説明します。0件の状態
フィルターは無効化し、路線0件・列車0件・絞り込み0件は同じ単一empty-state面へ出します。

現在地ボタンはユーザーがタップした時だけ`When In Use`権限を要求し、Core Locationの
one-shot結果をMapLibreのカメラ移動にだけ使用します。座標は永続化せず、APIや通知登録、
利用者投稿へ送信しません。`showsUserLocation`は無効のままで継続追跡せず、バックグラウンド
遷移時は取得中リクエストを通知なしで中止します。Reduce Motion時はカメラ移動を
アニメーションしません。

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

POSTは常にJSONで、KeychainのReporter IDを`X-Community-Reporter`へ設定します。
`403`はサーバー拒否、`413`は本文過大、`415`はJSON形式不一致として表示し、
`429`では`Retry-After`まで同一路線を再送できない状態にします。

## APNsバックエンドの残作業

iOSクライアント側はHTTPSの登録／解除に対応しますが、現行Webバックエンドには
APNs端末登録／配信処理がありません。`APNS_REGISTRATION_URL`には次を受ける
HTTPS `POST`を用意します。

```json
{
  "deviceToken": "<hex APNs token>",
  "lineIds": ["tokaido", "yamanote"],
  "platform": "ios",
  "bundleId": "com.shunsoco.trainlivemap"
}
```

購読全解除または通知許可無効時のHTTPS `DELETE`は次を受け、該当tokenの購読情報を
冪等に削除します。

```json
{
  "deviceToken": "<hex APNs token>",
  "platform": "ios",
  "bundleId": "com.shunsoco.trainlivemap"
}
```

`Content-Type`はどちらも`application/json`です。Web版の`/api/push/config`と
`/api/push/subscriptions`はWeb Pushのendpoint／p256dh／auth鍵を受けるブラウザ専用
APIなので、iOSから呼ばず、APNs tokenを送信しないでください。

必要なサーバー責務:

- tokenと購読路線のupsert／解除／失効token削除
- `updatedAt`基準でPush情報を最大180日だけ保持し、期限切れを削除
- 通知解除のDELETEでサーバー側購読情報を即時削除
- APNs provider tokenまたは証明書の安全な保管
- 直近5分、異なるReporterの最新票だけを1票として集計
- 見合わせ3件以上かつ60%以上
- 前5分の見合わせ票が多い場合は2倍以上（最低でも前窓+2件）
- 路線別クールダウンと通知重複防止
- お気に入り／通知登録路線だけへ送信
- payloadの`userInfo.lineId`
- 「可能性」「利用者からの報告」「公式情報をご確認ください」の文言

APNs key、Team ID、Key IDはGitへ保存せず、Vercel等のSecretへ設定します。
アプリ内プライバシー表示には、Push情報が最終更新から最大180日保持され、通知解除時に
サーバーから削除されることを明記します。

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

2026-08-01のフェーズ3〜6反映後に実測した結果:

- 実行先: iPhone 17 Pro Simulator／iOS 26.4
- Unit Test: 86件中86件成功、失敗0
- UI Test: 4件中4件成功、失敗0
- iPhone SE（第3世代）相当 UIスモーク: 1件中1件成功、失敗0
- Release Simulator build: 成功

次は過去フェーズで記録された確認であり、フェーズ3〜6反映後の現コードでは今回
再実行していません。App Store提出判定には上記の最新実測と、提出前の実機／端末別
再検証を使用してください。

最新コードではiPhone SE（第3世代）相当の主要操作／アクセシビリティUIスモークも
成功しました。Pro Max相当とiPadの追加試行はCoreSimulatorServiceのホスト側接続断で
アプリ起動前に終了したため、成功件数へ含めていません。

- iPhone SE相当、Pro Max相当、iPad Pro 11-inch相当のレイアウト／VoiceOver確認
- 本番APIモードのSimulator起動とODPTデータ描画
- Release実機向け署名なしコンパイル
- App Iconの全宣言サイズ／アルファと、M PLUS Rounded 3ウェイトの読込確認

自動テストの範囲:

- 4 APIレスポンスのCodable
- actual／estimated／mock、fallback
- 路線色、初期選択、検索、表示、お気に入り、通知対象、永続化
- 表示路線だけの公式運行情報
- 運転再開／現在見合わせの文脈分類、古い列車を除外した遅延補完
- 全状態フィルター
- 上下方向、顔、涙、遅延吹き出し、VoiceOver文言
- 補間、0〜1クランプ、線路投影、停止、Reduce Motion
- API失敗時の古いデータ明示とキャッシュ表示維持
- 過去の列車位置を地図・検索へ出さないオフライン処理
- 選択路線query、400／429／503再送抑止、Reporter ID形式
- 列車／運行情報のendpoint別再試行とCommunity GET／POST重複抑止
- 初回現在地権限ダイアログ中のscene inactivityとバックグラウンド停止
- 列車番号前方一致検索、0件フィルター、凡例、単一empty state
- 30分投稿集計、中央値、通知閾値

## 未設定の外部ID／提出前に必要な外部設定

| 項目 | 現在の状態 |
| --- | --- |
| Apple Developer Team／配布署名 | 未設定 |
| APNs Provider Keyまたは証明書／Team ID／Key ID | 未設定 |
| ネイティブAPNsバックエンド | 未提供 |
| `APNS_REGISTRATION_URL` | 未設定 |
| Release用`ADMOB_APP_ID` | 未設定 |
| Release用`ADMOB_BANNER_UNIT_ID` | 未設定 |
| UMPの地域別メッセージ | AdMob管理画面で公開前設定が必要 |
| App Store Connectのサポート／マーケティングURL | 提出前に設定が必要 |

プライバシーポリシーは`https://train-live-map.vercel.app/privacy`、利用規約は
`https://train-live-map.vercel.app/terms`へ設定済みです。上表の秘密情報や本物の
外部IDをGitへ追加せず、Apple、Vercel、AdMobの安全な設定から注入してください。

## 既知の制約

- ODPT列車位置は駅間推定で、実際のGPS走行位置とは異なる場合があります。
- `fromStation`／`toStation`がAPI未提供の場合、詳細は駅名なしの駅間推定表示です。
- 速度や停車開始時刻はAPI提供時だけ表示精度を保証できます。値を推測しません。
- 一部の選択可能路線はAPIに全線形状がありません。
- Webバックエンド、ODPT、CARTO、OpenStreetMap、Google広告の可用性に依存します。
- APNs端末登録／配信バックエンドは未提供です。
- バックグラウンド更新は意図的に実装していません。位置情報は現在地ボタン操作時の
  `When In Use` one-shotだけです。
- Release用AdMob ID、Apple署名、APNs外部設定は未設定です。

## App Store提出前チェックリスト

### Apple／署名

- Apple Developer Teamを設定
- Bundle ID `com.shunsoco.trainlivemap`を登録
- Push Notifications capabilityとAPNs key／証明書を設定
- Distribution certificate／profileまたはXcode Cloudを設定
- Release Archiveと実機で起動、投稿、通知deep linkを確認

### バックエンド／外部ID

- APNs端末登録URLのHTTPS POST／DELETEと送信workerを実装
- Push情報の最大180日失効と通知解除時削除をバックエンドで検証
- `APNS_REGISTRATION_URL`をReleaseへ注入
- AdMob App ID／Adaptive Banner Unit IDをReleaseへ注入
- UMPメッセージを必要地域向けに公開
- 本番APIの4エンドポイントとCORS／rate limitを再確認

### App Store Connect

- 掲載名、サブタイトル、説明、キーワード、カテゴリを確定
- サポートURLとマーケティングURLを設定し、既存のプライバシーポリシー／利用規約URLを確認
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
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' test
```

macOSのファイル調停でプロジェクト読込が遅い環境では、検証専用コピーまたは
`-derivedDataPath /tmp/train-live-map-ios-derived-data`を使用してください。
