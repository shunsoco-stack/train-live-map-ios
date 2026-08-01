# Train Live Map for iOS

関東を走るJR東日本の列車位置推定と運行状況を地図で確認する、SwiftUI製ネイティブアプリです。

画面上の正式表記は次のとおりです。

```text
Train Live Map
JR東日本・関東版（非公式）
```

- ホーム画面表示名: `Train Live Map`
- Bundle ID: `com.shunsoco.trainlivemap`
- 対応OS: iOS 17以降
- 問い合わせ: `train-live-map-support@gmail.com`
- App Store掲載名候補: `Train Live Map - JR東日本 関東版`

JR東日本の公式アプリではありません。WebViewは使用しておらず、既存Web版
[`shunsoco-stack/train-live-map`](https://github.com/shunsoco-stack/train-live-map)
を仕様参照元として独立実装しています。Web版リポジトリへiOSコードは追加しません。

## 実装済み機能

- MapLibre Native上へAPI取得路線だけを路線色・外枠付きで描画
- 線路方向に沿い、上下逆を補正した路線名ラベル
- 路線検索、表示／非表示、全表示／全非表示、選択数表示
- 表示路線とお気に入りを別々に永続化し、「お気に入りのみ」で絞り込み
- APIカテゴリごとに利用可能な先頭1路線だけを初回表示
- 走行中、停車中、遅延、運転見合わせの列車フィルター
- 列車番号の前方一致検索、選択列車への地図移動と詳細表示
- 明示タップ時だけ現在地を取得し、保存・送信せず地図を移動する現在地ボタン
- 列車状態、上り／下り、駅間推定位置を説明する地図凡例
- 状態別の電車の顔、上下方向文字、遅延吹き出し、見合わせバッジ
- 列車詳細Bottom SheetとVoiceOver向け読み上げ
- `routeSegment`／路線ポリライン上へクランプした滑らかな位置補間
- 表示路線だけを対象にした公式運行情報と、最新列車遅延による安全な補完
- 直近30分の「みんなの運行情報」と匿名投稿
- ユーザー操作後だけ要求する通知許可、HTTPS専用のAPNs端末登録／解除クライアント
- 最終成功レスポンスの端末キャッシュと、失敗時の更新時刻表示／再試行
- オンライン更新失敗時は最終成功位置を「古いデータ」と明示して保持し、オフライン時は非表示
- バックグラウンド時のポーリング・アニメーション停止、復帰時の即時更新
- M PLUS Rounded 1c、ライト／ダーク、Dynamic Type、Reduce Motion、
  Reduce Transparency、iPhone／iPad対応
- UMP同意取得後にだけ初期化するAdMobアダプティブバナー

地図の列車位置はGPS現在地ではありません。ODPTの駅間情報などから求める場合が
あるため、アプリには常に「ODPTライブ（位置は駅間推定）」と表示します。

## 技術構成

- Swift / SwiftUI
- MVVM + Repository
- async/await + URLSession + Codable
- MapLibre Native for iOS 6.28.0
- Google Mobile Ads SDK 13.7.0
- Google User Messaging Platform 3.1.0
- Swift Package Manager
- UserDefaults + Application Support JSONキャッシュ
- XCTest / XCUITest
- XcodeGen

依存方向は次のとおりです。

```text
View
  ↓
ViewModel
  ↓
TrainRepository
  ↓
TrainAPIService
  ↓
WebバックエンドAPI
```

UIから通信、キャッシュ、集計ロジックを分離しています。

## セットアップ

必要環境:

- Xcode 16以降
- XcodeGen
- iOS 17以降のSimulator、またはiPhone／iPad

```sh
brew install xcodegen
xcodegen generate
open TrainLiveMap.xcodeproj
```

Xcodeで`TrainLiveMap`スキームを選んで実行してください。`project.yml`がプロジェクト
設定の正本です。ターゲットやSwift Packageを変更した場合は、生成後の
`TrainLiveMap.xcodeproj`もコミットします。

## 環境設定

既定値は`Config/Base.xcconfig`、Debug／Release差分は各xcconfigにあります。

| 設定 | 既定値／挙動 |
| --- | --- |
| `API_BASE_URL` | `https://train-live-map.vercel.app` |
| `APNS_REGISTRATION_URL` | 未設定 |
| `ADMOB_APP_ID` | DebugはGoogle公式テストID、Releaseは未設定 |
| `ADMOB_BANNER_UNIT_ID` | DebugはGoogle公式テストID、Releaseは未設定 |
| `MARKETING_VERSION` | `1.1.0` |

Release用の外部IDはGit管理外のファイルから注入します。

```sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

`Config/Secrets.xcconfig`は`.gitignore`対象です。API URLをxcconfigへ記述する場合、
`//`がコメント扱いされないよう`https:/$()/example.com`形式を使います。
`API_BASE_URL`と`APNS_REGISTRATION_URL`は`https` URLだけを許可します。`http`や
不正なURLは通信へ使用しません。

## バックエンドAPI

アプリが直接利用するのは、Web版バックエンドの次のAPIだけです。

| Method | Path | 用途 | 更新 |
| --- | --- | --- | --- |
| GET | `/api/trains?lines=...` | 選択路線の列車スナップショット | 10秒 |
| GET | `/api/service-status?lines=...` | 選択路線の公式運行情報 | 10秒 |
| GET | `/api/railways` | 路線形状と選択肢 | 起動時 |
| GET | `/api/community-reports` | 利用者投稿の30分集計 | 10秒／シート表示時 |
| POST | `/api/community-reports` | 匿名Reporter IDによる投稿 | ユーザー操作時 |

`/api/trains`では`trains`に加えて`generatedAt`、`dataUpdatedAt`、`isMock`、
`source`、`fallback`、`notice`をデコードします。列車モデルは`routeSegment`、
`fromStation`、`toStation`、`railDirection`の有無にも対応します。

列車と公式運行情報には、`/api/railways.options[].id`から選択中のIDだけを昇順で
連結し、`?lines=tokaido,yamanote`形式で渡します。IDは重複を除き、
`^[a-z0-9-]{1,64}$`、最大44路線、クエリ値1,024文字以内を通信前にも検証します。
表示路線が0件なら両APIを呼びません。`serviceStatuses`がレスポンスに存在する場合は、
空配列でも互換用`serviceStatus`へフォールバックせず、その空配列を選択路線の結果として
扱います。

`/api/railways`の`lines`を地図描画に使用し、`options.available`と`coverage`を
選択可否、`coverageNote`を提供範囲の注意書きに使用します。路線一覧や利用可否を
iOS側の固定値だけでは決めません。起動直後は保存済みカタログを選択画面の復元に
使えますが、選択路線の列車・運行情報を取得する前に`/api/railways`を1回更新し、
削除・名称変更・利用可否をサーバーの最新結果へ整合します。更新失敗時はキャッシュを
フォールバック表示し、キャッシュがなければ自動ポーリングを開始せず再試行を案内します。

`/api/service-status`のODPT明示情報を最優先します。公式情報が平常または空相当の
場合だけ、同一路線で更新2分以内のODPT列車を確認し、遅れがあれば平常表示を
補正します。最大30分以上、または全列車の半数以上が15分以上遅れている場合は
大幅な遅れとして案内します。列車遅延だけから運転見合わせとは判定せず、運転再開
文面は遅延、現在も運転を見合わせている明示文面だけを見合わせとして扱います。

iOSアプリからODPTへ直接アクセスしません。`ODPT_ACCESS_TOKEN`をソース、
Info.plist、xcconfig、ログ、Git履歴へ保存しないでください。トークン管理と
ODPT失敗時のフォールバックはVercel側の責務です。

利用者投稿は`Content-Type: application/json`で送信し、Keychainへ保存した
ランダムなReporter IDを`X-Community-Reporter`ヘッダーへ設定します。サーバーの
`403`（拒否）、`413`（本文過大）、`415`（JSON以外）、`429`（回数制限）は個別に
案内します。`429`では`Retry-After`の秒数または日時までクライアント側でも再送を
禁止し、自動リトライしません。Reporter IDをKeychainへ保存できない場合は投稿を
fail-closedで中止します。

Reporter IDは送信のたびに`^[A-Za-z0-9_-]{12,100}$`へ適合することを確認します。
列車・運行情報APIの`400`は路線選択が変わるまで、`429`は`Retry-After`まで、
`503`は`Retry-After`または次の通常10秒周期まで再送しません。同じエンドポイントの
処理中要求、ボタン連打、再帰的な自動リトライも行いません。

`ODPT_ACCESS_TOKEN`、Redis認証情報、`VAPID_PRIVATE_KEY`、
`REPORTER_HASH_SALT`、移行用の`COMMUNITY_REPORT_HMAC_SECRET`はすべて
Webバックエンドだけで管理する秘密情報です。iOSアプリ、Info.plist、xcconfig、
ログ、Git履歴へ組み込みません。

## 実データ・推定・モックの区別

`dataAccuracy`とレスポンスメタデータを次のように表示します。

- `actual`: 実データ
- `estimated`: 推定データ（駅間推定）
- `mock`: モックデータ
- `isMock == true`または`source == mock`: 「モックデータ使用中」
- `fallback == true`: フォールバック理由と`notice`

ODPTのJR東日本列車位置は公共交通オープンデータチャレンジ2026限定データです。
`odpt:Train`には緯度経度がなく、`fromStation`／`toStation`から線路上の位置を
推定する場合があります。実測GPS位置と誤認させる「現在地」という表現は使いません。

## 対象路線

対象は`/api/railways.options`で`available == true`かつ
`coverage != unavailable`の路線です。2026-07-30の本番API確認時点では、
41選択肢中40路線が選択可能で、次の7カテゴリでした。

- 山手線: 山手線
- 直通系統: 湘南新宿ライン、相鉄線直通列車
- 東海道方面: 東海道線、京浜東北線、横須賀線、南武線、横浜線、伊東線
- 東北・高崎方面: 宇都宮線、高崎線、埼京線、川越線、武蔵野線、上越線、
  信越本線、吾妻線、烏山線、日光線、両毛線
- 中央方面: 中央線快速電車、中央・総武線各駅停車、中央本線、五日市線、
  青梅線、小海線
- 常磐方面: 常磐線、常磐線快速電車、常磐線各駅停車、水郡線、水戸線
- 総武方面: 総武快速線、総武本線、京葉線、内房線、鹿島線、久留里線、
  外房線、東金線、成田線

同時点で上野東京ラインは`available == false`のため選択画面から除外されます。
既知の対象外である相模線、鶴見線、南武支線、八高線もAPIの利用可能選択肢へ
含まれないため表示しません。APIが変更された場合は最新結果を優先します。

高崎線、中央本線、青梅線、常磐線系統など、`coverage == limited`の路線には
APIの`coverageNote`を表示します。

## 更新、キャッシュ、列車アニメーション

- 列車: 10秒
- 公式運行情報: 10秒
- みんなの運行情報: 10秒
- 路線: 起動時
- バックグラウンド: 全ポーリングと補間を停止
- フォアグラウンド復帰: 即時更新

成功レスポンス4種はApplication Support配下へ原子的に保存します。通信失敗時も
キャッシュと最終更新時刻を保持します。オンライン中の一時的なAPI失敗では、最後の
成功位置を地図・検索・詳細に残し、「古いデータ」、最終更新、エラーを同時表示します。
端末がオフラインになった場合だけ、過去座標を現在位置として扱わないよう列車を
地図・検索・詳細から隠し、ネットワーク復帰時に即時取得し直します。
停止時間の表示だけを1秒ごとに局所更新し、地図や画面全体を1秒周期で更新しません。

列車位置は`routeSegment.coordinates`を優先し、なければ緯度経度を選択路線の
ポリラインへ投影します。進行方向と区間の`fromFraction`／`toFraction`を使い、
現在の描画位置から次スナップショットへ補間します。停止中・見合わせ中・
バックグラウンド・Reduce Motion有効時は動かしません。次駅や駅間終端を越えて
外挿せず、API更新が止まった後に予測移動を続けません。

## みんなの運行情報

- 投稿種別: 平常、遅延、運転見合わせ
- 遅延分数: 1〜120分、集計値は中央値
- 集計窓: 直近30分
- 同数: 重大度の高い状態を優先
- Reporter ID: ランダムUUID由来の値をKeychainへ保存し、個人情報は収集しない
- 連続投稿: API返却の`cooldownSeconds`を端末でも適用
- 表示: 「みんなの情報（非公式）」と明記し、公式運行情報と分離

POST本文は`lineId`、`status`、必要時の`delayMinutes`です。JSON本文とともに匿名IDを
`X-Community-Reporter`ヘッダーへ設定します。バックエンド側でも入力検証、
匿名化、永続化、レート制限を行う前提です。Reporter IDをログへ出力しません。

## APNs通知

通知許可は通知設定シートで機能説明を読んだ後、ユーザー操作でだけ要求します。
お気に入りと通知対象は別々に保存し、通知タップ時は`userInfo.lineId`の路線だけを
表示します。

iOS側は`APNS_REGISTRATION_URL`へ次のJSONを`POST`して端末登録／購読更新します。

```json
{
  "deviceToken": "<APNs token>",
  "lineIds": ["tokaido"],
  "platform": "ios",
  "bundleId": "com.shunsoco.trainlivemap"
}
```

全路線の通知を解除した場合または通知許可が無効になった場合は、同じURLへ
`deviceToken`、`platform`、`bundleId`をJSONで`DELETE`し、サーバー側購読情報も
削除します。

Web版の`/api/push/config`と`/api/push/subscriptions`はブラウザのWeb Push専用です。
iOSアプリはこれらを呼ばず、APNsデバイストークンを絶対に送信しません。現行Web
バックエンドにはネイティブAPNs用のPOST／DELETE／配信エンドポイントがないため、
`APNS_REGISTRATION_URL`未設定時は通知許可と購読路線だけを端末へ保存します。
サーバー側では、直近5分の異なるReporterによる見合わせ票3件以上、割合60%以上、
前5分にも票が多い場合は2倍以上、路線別クールダウン、重複防止を実装してから
本番URLを設定してください。Push購読情報は最終更新から最大180日で失効させ、
通知解除の`DELETE`およびAPNsの失効応答で直ちに削除します。アプリ内プライバシー表示
にもこの保持期間と削除方法を明記します。通知文は必ず「可能性」「利用者からの報告」
と明記します。

## AdMobとUMP

[Google Mobile Ads SDK公式手順](https://developers.google.com/admob/ios/quick-start)
に沿ってSPM導入しています。

DebugはGoogle公式テストIDだけを使用します。

- App ID: `ca-app-pub-3940256099942544~1458002511`
- Adaptive Banner: `ca-app-pub-3940256099942544/2435281174`

Release用IDが未設定なら広告SDKを初期化せず、バナー領域も表示しません。設定済みでも
UMPの同意情報を更新し、必要なフォームを提示し、広告リクエスト可能になってから
Google Mobile Ads SDKを初期化します。本物の広告IDをGitへコミットしないでください。

## デザインとアクセシビリティ

- M PLUS Rounded 1c Regular 400／Bold 700／ExtraBold 800
- Web版と統一した緑色の電車App Icon（全iPhone／iPadサイズ、アルファなし）
- ダークブラウンのヘッダー／パネル、東海道線アクセント`#f68b1e`
- 44pt以上のタップ領域、Dynamic Type、十分なコントラスト
- 状態を色だけでなく、顔・文字・記号・VoiceOverで表現
- Reduce Motion時は列車補間を無効化
- Reduce Transparency時はパネルの不透明度を上げる
- 位置情報は現在地ボタンのタップ後にだけ「使用中のみ」を要求し、地図移動後に追跡しない
- 端末の現在地は保存・サーバー送信せず、列車の推定座標も地図表示・移動以外のAPIへ追加送信しない

アプリ内から[プライバシーポリシー](https://train-live-map.vercel.app/privacy)と
[利用規約](https://train-live-map.vercel.app/terms)を開けます。

## ビルドとテスト

```sh
xcodegen generate

xcodebuild \
  -project TrainLiveMap.xcodeproj \
  -scheme TrainLiveMap \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project TrainLiveMap.xcodeproj \
  -scheme TrainLiveMap \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Simulatorテストは、インストール済みのOSと端末名へ変更して実行します。

```sh
xcodebuild \
  -project TrainLiveMap.xcodeproj \
  -scheme TrainLiveMap \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  test
```

2026-08-01のフェーズ3〜6最終検証結果:

- 実行先: iPhone 17 Pro Simulator／iOS 26.4
- Unit Test: 86件中86件成功、失敗0
- UI Test: 4件中4件成功、失敗0
- Release Simulator build: 成功

この最終検証で実行した端末はiPhone 17 Proです。iPhone SE相当、Pro Max相当、
iPadのレイアウトシナリオもテストコードと過去フェーズの確認対象に含まれますが、
フェーズ3〜6反映後の現コードを使った最新の端末別実測とは区別してください。
追加のiPhone SE Simulator実行はCoreSimulatorサービスのホスト側IPCエラーで起動前に
終了したため、アプリのテスト成功としては数えていません。

テスト対象にはAPIデコード、実／推定／モック、路線カラー、選択・検索・お気に入り、
列車番号の前方一致検索、0件フィルター、単一の空状態、状態フィルター、
補間・クランプ、顔・吹き出し・方向、キャッシュ、投稿集計、
Community APIのJSON／Keychain／HTTPエラー／再送制限、APNs登録・解除契約、
同一GET／POSTの重複抑止、初回現在地許可中のscene遷移、通知判定、Reduce Motion、
VoiceOver文言、最大Dynamic Type、ダークモード、
小型iPhone／標準／Pro Max／iPadを想定したレイアウトシナリオが含まれます。

## 未設定の外部項目

ソース、Info.plist、xcconfig、Gitへ本物の秘密情報や外部IDは固定していません。
App Store提出までに次を外部環境で設定してください。

- Apple Developer Team、配布証明書／Provisioning Profile
- APNs Provider Keyまたは証明書、Team ID、Key ID
- ネイティブAPNs登録／解除／配信バックエンドと`APNS_REGISTRATION_URL`
- Release用`ADMOB_APP_ID`と`ADMOB_BANNER_UNIT_ID`
- 必要地域向けのUMPメッセージ
- App Store ConnectのサポートURL、マーケティングURL、掲載メタデータ

プライバシーポリシーと利用規約のURLは設定済みです。APNs、AdMob、Apple署名が
未設定でも、該当機能を安全に無効化した状態でアプリ本体とテストをビルドできます。

## データと地図のクレジット

- 公共交通オープンデータセンター（ODPT）:
  [開発者サイト](https://developer.odpt.org/)、
  [データカタログ](https://ckan.odpt.org/)
- OpenStreetMap:
  [Copyright and License](https://www.openstreetmap.org/copyright)
- CARTO:
  [Attributions](https://carto.com/attributions)

ODPTチャレンジ2026およびデータ提供者ごとの利用条件に従ってください。MapLibreの
ロゴと帰属ボタンは非表示にしておらず、スタイルにも
`© OpenStreetMap contributors, © CARTO`を設定しています。

## ディレクトリ構成

```text
TrainLiveMap/
├── App/                 起動と環境設定
├── Data/                API Client、Repository、キャッシュ、端末設定
├── Domain/              Codableモデル、集計、補間、表示ロジック
├── Design/              色、M PLUS Rounded、共通スタイル
├── Features/
│   ├── About/
│   ├── Ads/
│   ├── Community/
│   ├── Filters/
│   ├── Main/
│   ├── Map/
│   ├── Notifications/
│   ├── Search/
│   └── Train/
└── Resources/           App Icon、フォント、MapLibreスタイル
```

リリース時の外部設定と既知の制約は[HANDOFF.md](HANDOFF.md)を参照してください。
