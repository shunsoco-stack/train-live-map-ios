# Train Live Map iOS 引き継ぎ

更新日: 2026-10-27。1.1.0(3)の署名付きProduction Archive・IPA作成とアップロードが完了。TestFlightで「提出準備完了」を確認し、App Store版1.1.0へ関連付け済みです。審査提出・公開は未実施です。

## リポジトリと環境

- iOS: https://github.com/shunsoco-stack/train-live-map-ios
- iOS作業ブランチ: `release/app-store-readiness`
- Web API: https://github.com/shunsoco-stack/train-live-map
- Web PR #9: 所有者の明示承認後にmainへマージ、本番反映済み。マージコミット `896aebeb8c63ee4457770f42ad05548360c3fadf`
- Xcode 26.4、SDK iOS 26.4、Deployment Target iOS 17
- SwiftUI、MVVM、Repository、async/await、MapLibre Native 6.28.0、SPM
- プロジェクト正本: `project.yml`。生成済み `TrainLiveMap.xcodeproj` を同梱
- 確定Bundle ID: `com.shunsoco.trainlivemap`
- Version 1.1.0、Build 3。Developer Teamは確認済みのLC47V8NZP6

## 実装

地図はOpenFreeMap Positronを読み込みます。失敗時は背景色#E8EAEDのローカルスタイルへフォールバックし、路線・駅・列車を維持します。OpenFreeMap、OpenMapTiles、OpenStreetMapの帰属リンクを常時表示します。CARTOタイルは使いません。

駅名・駅イラスト、路線色、路線名、列車の顔・方向・遅延表示、線路上の位置補間、重なりオフセットを実装。推定位置・モック・古い情報を区別します。開発用モックはUIテスト時だけ使い、画面にも明記します。

路線検索、エリア分類、お気に入り、絞り込み、全選択・解除をUserDefaultsで保存。初回は各方面の先頭の利用可能路線だけを選択。列車位置対象外路線を生成しません。

公式情報を独立したシートで確認でき、提供元と更新時刻を表示します。新鮮な公式の全線見合わせは列車の見合わせ状態にも反映します。一部区間の見合わせで全列車を停止扱いにせず、再開見込みを再開済みと判定しません。

利用者投稿には平常・遅れ・大幅遅延・見合わせ・再開を用意。再開は既存APIのon-time票に任意のeventを追加する互換方式です。投稿は公式情報と分け、匿名のランダム識別子をKeychainへ保存して送信します。サーバーと端末の両方で連続投稿を制限します。

通知設定は有効化、対象路線、公式のみ／利用者報告も含む、見合わせ・再開・遅延を保存。ユーザー操作後だけ権限を要求します。APNsクライアントは所有秘密値をKeychainに保持して登録・解除し、設定更新を直列化します。

広告SDKと広告ID・SKAdNetwork設定は除去済み。ATT・広告配信・解析SDKはありません。位置情報はボタン操作後の使用中許可のみで、アプリのサーバーへ送信しません。

## APIと秘密情報

既存の `/api/railways`、`/api/trains?lines=...`、`/api/service-status?lines=...`、`/api/community-reports` を使用します。型はWebコードと実際の本番レスポンスを照合しました。iOSにODPT_ACCESS_TOKENやサーバー秘密情報を埋め込みません。HTTPSのみ、ATS例外なし。OSLogにはHTTPステータスだけを記録します。

Web側の別変更で `/api/apns/devices`（POST/DELETE）と `/api/apns/dispatch`（認証付きGET）を追加。AES-256-GCM、所有者ハッシュ、Redisの原子的更新・回数制限、180日失効、無効トークン削除、状態変化・利用者報告急増の判定を実装しました。詳細はWebの `docs/native-apns.md`。

本番Vercelの環境変数名を確認したところAPNs設定は未提供でした。APNS_REGISTRATION_URLは空のままで、配信は既定で無効です。鍵の新規作成・本番Push送信・本番データ削除はしていません。

## 環境の切替

Development、Staging、Productionのxcconfigを用意。DebugはDevelopment、Release/ArchiveはProductionを使用します。Staging専用URLは未提供のため現状は本番読み取りAPIです。実環境URLを上書きしてください。

`Config/Signing.local.xcconfig`、`Config/Secrets.xcconfig` はGit対象外。Apple Teamは確認済み。秘密鍵をxcconfigへ保存してはいけません。

## 検証済み

- 最新のiOS Unit Test: 89/89成功
- 最新のiOS UI Test: 6/6成功、iPhone 17 Pro / iOS 26.4
- iPhone SE第3世代: スモークと最大文字サイズ／ダークモードの2/2成功
- 最終地図調整後のiPhone 17 Pro Max: スモーク1/1成功（TrainLiveMapFinalUITests20261025.xcresult）
- iPadビルド3: 基本地図スモーク成功。最大文字サイズ・ダークモード・通知説明は初回UIスナップショット取得タイムアウト、単独再実行1/1成功。2ケースとも成功結果あり。実データ地図を目視確認済み
- UI: 初回・路線検索・お気に入り・公式情報・投稿・列車詳細・通知・オフライン・最大文字サイズとダークモード
- Productionの署名なし最終Archive: 成功、アプリ約20.2MB
- Productionの署名付き最終ArchiveとIPA書き出し: 成功、IPA約10MB
- 配布署名のBundle ID／Teamとproduction APNs、get-task-allow=falseを確認
- アプリとMapLibre双方のPrivacyInfo.xcprivacyがArchiveに存在
- Web既存＋再開互換テスト: 107/107成功
- Web APNs検証・通知判定・暗号化・環境別JWTテスト: 9/9成功
- Web TypeScript/本番ビルド、ESLint: 成功
- Web本番依存関係: npm audit --omit=devで脆弱性0
- ローカル配信APIは認証なしGETを401で拒否
- Web MapLibre v6のWorker修正後、背景地図・駅・列車・詳細を目視確認

テスト成果物は `/private/tmp/TrainLiveMapTests20261025-C.xcresult` と `/private/tmp/TrainLiveMapUITests20261025-D.xcresult`。一時ディレクトリなので長期保管先ではありません。

## 提出までの残作業

1. 接続iPhoneで地図、権限、復帰、通信切替、VoiceOver、メモリ・バッテリーを検証
2. APNs鍵・環境変数・定期実行環境を設定し、開発用端末で登録、受信、解除を検証。鍵作成・本番通知送信は確認対象
3. プライバシー申告をホスティング実設定と照合して確定。Vercel接続ツールはプロジェクト参照不可、Chromeログイン待ち
4. App Store Connectの画像、プライバシー公開、配信対象プラットフォームの最終確認
5. 所有者の確認後に審査提出し、Apple承認後に公開。審査提出・公開は未承認

ODPTチャレンジ応募予定と第三者コンテンツの権利申告、無料・日本のみ、端末IDの関連付けあり／機能目的／トラッキングなしは所有者承認済み。ODPTの現行期限2027-03-12と条件はRelease/Data-License-Review.txtを参照。

`Release/AppStore-ja.txt` と `Release/Privacy-Inventory.txt` に掲載文・審査メモ・Privacy Nutrition Labels案があります。提出操作と公開は未実施で、Appleの審査結果も未取得です。

Apple DeveloperにApp ID com.shunsoco.trainlivemapを登録済み（Push Notifications有効）。新しい証明書は未作成。iOS PR: https://github.com/shunsoco-stack/train-live-map-ios/pull/1 、Web PR: https://github.com/shunsoco-stack/train-live-map/pull/9 。

## 署名・Apple登録の現状

- App Store Connect: https://appstoreconnect.apple.com/apps/6826815750/distribution/ios/version/inflight
- 1.1.0の説明文、サブタイトル、キーワード、サポートURL、審査連絡先、審査メモを保存済み。個人の電話番号はリポジトリへ記録しない
- カテゴリはナビゲーション／旅行。審査後は手動公開に設定済み
- 配布プロファイル: Train Live Map App Store 20261025（既存配布証明書使用）
- 開発プロファイル: Train Live Map Development 20261025（既存開発証明書、登録済みiPhone 16 Pro Max使用）
- 最終Archive: Artifacts/20261027/TrainLiveMap-1.1.0-3.xcarchive
- IPA: Artifacts/20261027/TrainLiveMap-1.1.0-3.ipa（Git対象外）
- ExportOptions: Release/ExportOptions.plist
- MacとApple認証は復旧済み。iPhone実機は2026-10-27 00:44 JSTのdevicectl確認でavailable (paired)。ビルド3の開発用署名ビルドとインストールは成功。初回起動確認はCoreDevice 10004。07:06 JSTの再試行では起動成功とMLNMapView初期化ログを確認し、45秒の観測中に終了ログなし。実機の基本操作と描画は下記の追加テストで確認済み。APNs受信、VoiceOverの実際の読み上げ、長時間のメモリ・バッテリー測定は未完了。

実データの初期表示で広域路線を全体表示するとアイコンが密集したため、広域の複数路線は東京付近から表示するよう調整。運行情報パネルは1件を要約し、全件はタップ先の画面で確認する。


## 2026-10-27 更新

- ビルド3は初期ズーム12へ変更し、推定情報を公式と誤解しないカード文言へ修正。シミュレータビルド、署名付きProduction Archive、IPA書き出し成功。iPhoneのお気に入り／運行情報UIテスト1/1成功。89件の単体テストと既存UI検証は前ビルドでの結果。
- Transporterで00:10 JSTにビルド3をデリバリ済み。App Store Connectでも処理完了「提出準備完了」を確認し、提出版へ関連付けて保存済み。
- 実データ画像: iPhone 6.9インチ（1320×2868）、iPhone 6.3インチ（1206×2622）、iPad 13インチ（2064×2752）をRelease/Screenshotsへ保存。App Store Connectへ各1枚登録済み。
- 年齢制限4+、第三者コンテンツの権利保有、無料、日本のみ配信を保存済み。子ども向けカテゴリは選択していない。
- プライバシーはOther User ContentとDevice IDを、App Functionality／Linked Yes／Tracking Noとして下書き保存。申告全体の公開は未実施。
- Web PR #9を承認後にマージ。Vercel本番チェック成功、公開/supportと/privacyのHTTP成功・iOS記載・問い合わせ先を確認。本番通知は無効、送信していない。
- Web Native Pushテスト9/9、型チェック・対象ESLint成功（既存107件と合計116件）。Sandbox／Production別APNs鍵、JWTキャッシュ分離と設定不備の拒否を含む。鍵の作成は未実施。
- 証跡画像はGit対象外のArtifacts/20261027へ保存。審査連絡先電話番号をGitに含めない。

- 初回配信対象はiPhone・iPad。MacとApple Vision Proの自動配信設定は無効にして保存。
- APNs専用鍵はSandbox／Production各1個、対象com.shunsoco.trainlivemapだけの作成を所有者へ確認中。Apple画面でSandboxの対象を選択済みだが、保存・登録・鍵作成は未実施。

## 2026-10-27 実機UI確認

- 接続したiPhone 16 Pro Max（iOS 26.6）で `testLiveBackendMapAndForegroundRecovery` が1/1成功、スキップ0。ODPTの本番データ、地図の帰属3件、路線選択シート、バックグラウンド復帰を確認。
- 実機スクリーンショットを目視確認し、OpenFreeMap背景・駅・路線・列車、推定表示、非公式表記、帰属を確認。朝の列車が多い時間帯では密集するため、路線絞り込み／ズームによる確認が必要。
- 結果: `/private/tmp/TLMLiveDevice20261027.xcresult`。画像は `Artifacts/20261027/DeviceUI/`（Git対象外）。
- 実機テストの署名だけを変更した一時コピーを使用。アプリの63ソース／リソースは元とハッシュ一致。既存のアプリ用開発プロファイルとテスト用標準プロファイルを使用し、新規証明書は作成していない。
- 追加テストは `TLM_LIVE_UI_TESTS=1` をテストランナーの環境に設定したときだけ実行する。投稿、現在地・通知権限要求、Push送信は行わない。通常のテスト実行ではスキップ。
- APNs鍵作成承認とVercelログインを待つ。審査提出・公開、長時間の電力測定、VoiceOver読み上げ、APNs実受信は未完了。
