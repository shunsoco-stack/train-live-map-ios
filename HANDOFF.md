# Train Live Map iOS 引き継ぎ

## 現在の状態

SwiftUIネイティブアプリ、MapLibre地図、3つの本番API、端末キャッシュ、路線設定、列車詳細、状態別アイコン、位置補間、AdMobテスト広告、UMP同意フロー、XCTestを実装済みです。

既存Web版`shunsoco-stack/train-live-map`は仕様確認だけに使用し、変更していません。iOSコードは独立した`shunsoco-stack/train-live-map-ios`で管理します。

## 主要設定

| 項目 | 値 |
| --- | --- |
| 表示名 | Train Live Map |
| Bundle ID | `com.shunsoco.trainlivemap` |
| Deployment Target | iOS 17.0 |
| API Base URL | `https://train-live-map.vercel.app` |
| 列車更新 | 7秒 |
| 運行情報更新 | 30秒 |
| 路線更新 | 起動時 |

`project.yml`がXcodeプロジェクトの正本です。ターゲットやパッケージ設定を変えた後は`xcodegen generate`を実行し、生成された`TrainLiveMap.xcodeproj`もコミットしてください。

## 実装責務

- `MainViewModel`: キャッシュ読込、即時更新、7秒／30秒ポーリング、バックグラウンド停止、エラー状態
- `URLSessionTrainAPIService`: Vercel APIだけへGETし、HTTPとJSONを検証
- `FileResponseCache`: 最終成功レスポンス3種の端末保存
- `UserPreferences`: 表示路線、お気に入り、お気に入りのみをUserDefaultsへ保存
- `TrainMotionEngine`: routeSegment優先、ポリライン投影、0〜1クランプ、現在位置からの補間、停止
- `MapLibreTrainMap`: 路線ポリライン、列車Annotation、選択、OSM/CARTO帰属
- `TrainIconView`: 路線色、方向文字、顔、遅延／見合わせバッジ
- `AdManager`: UMP同意情報、同意フォーム、許可後の広告SDK初期化

位置補間では、座標付き`routeSegment`の配列順、または座標なし区間の`fromFraction → toFraction`を進行方向として扱います。推定中の列車は区間終端の手前まで最大6.2秒で動き、その後停止します。新しいレスポンスではその時点の描画位置から接続します。停止中、運転見合わせ、バックグラウンド、データ更新停止後には外挿しません。

## APIとフォールバック

アプリが直接利用するのは次だけです。

- `/api/trains`
- `/api/service-status`
- `/api/railways`

ODPTへ直接アクセスするコードやトークン設定を追加しないでください。`isMock`、`source`、`fallback`、`notice`は画面上の警告表示へ反映しています。路線選択は`options.available`を操作可否に、`options.coverage`と`coverageNote`を説明表示に使用します。

APIモデルを変更する場合は、既存Web版の`src/types`とAPI実装、本番レスポンス、`TrainLiveMapTests/Fixtures`を同時に確認してください。

## 永続データ

UserDefaultsキー:

- `train-live-map.visible-line-ids`
- `train-live-map.favorite-line-ids`
- `train-live-map.favorites-only`
- `train-live-map.visibility-initialized`

APIキャッシュはApplication Support内の`TrainLiveMap/Cache`へ保存します。

## AdMobリリース手順

DebugはGoogle公式テストIDだけを使います。Release用IDはリポジトリに入っていません。

1. `Config/Secrets.xcconfig.example`を`Config/Secrets.xcconfig`へコピーする。
2. Release用`ADMOB_APP_ID`と`ADMOB_BANNER_UNIT_ID`を設定する。
3. 対象地域のUMPメッセージをAdMob管理画面で公開する。
4. 同意フォーム、プライバシー設定ボタン、バナー表示を実機で確認する。
5. `Config/Secrets.xcconfig`がGit管理外であることを確認する。

IDが空の場合、Releaseでは広告領域自体が非表示です。

## App Icon

可愛い正面向きの電車の顔をモチーフにした生成画像を、`TrainLiveMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`へ1024×1024で保存しています。路線アクセントのオレンジ、丸い車体、ダークブラウン背景を使用しています。

## 検証

XCTestは`TrainLiveMapTests`にあります。Simulatorのテストでは次を網羅します。

- 本番仕様に合わせた3 APIのデコード
- 状態と顔、方向、VoiceOver文言
- 路線検索、available、coverage、表示、お気に入り、永続化
- 全列車状態フィルター
- 進行方向別補間、線路クランプ、更新停止後の静止
- API失敗時のキャッシュ維持
- mock／fallback警告

リリース前には次を再確認してください。

```sh
xcodegen generate
xcodebuild -project TrainLiveMap.xcodeproj -scheme TrainLiveMap \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
xcodebuild -project TrainLiveMap.xcodeproj -scheme TrainLiveMap \
  -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Apple Developer Teamと署名はリポジトリへ固定していません。App Store配布時にXcodeまたはCIの安全な設定から注入してください。

## 既知の制約

- 列車位置はGPS実測とは限らず、駅間情報などからの推定です。
- Vercel API、CARTOタイル、OpenStreetMapデータ、Google広告サービスの可用性に依存します。
- バックグラウンド更新や位置情報権限は意図的に実装していません。
- Release用AdMob ID、Apple Developer Team、配布署名は外部設定が必要です。
- App Store提出前に最新のGoogle SKAdNetwork ID一覧、プライバシーマニフェスト、ストア向けプライバシー回答を再確認してください。
