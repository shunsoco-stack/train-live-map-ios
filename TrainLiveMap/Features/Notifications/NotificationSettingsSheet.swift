import SwiftUI
import UIKit

struct NotificationSettingsSheet: View {
    let options: [RailwayFilterOption]
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var notificationManager: NotificationManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var unregisterConfirmationPresented = false
    @State private var isUnregistering = false

    var body: some View {
        NavigationStack {
            List {
                explanationSection
                notificationTypesSection
                authorizationSection
                routeSection
                backendSection
                privacySection
            }
            .navigationTitle("運行情報の通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .font(RailFont.bold(.body))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .mplusAppTypography()
        .alert(
            "通知登録を解除しますか？",
            isPresented: $unregisterConfirmationPresented
        ) {
            Button("キャンセル", role: .cancel) {}
            Button("解除", role: .destructive) {
                Task {
                    isUnregistering = true
                    await notificationManager.unregisterFromServer()
                    preferences.clearNotificationLineIDs()
                    isUnregistering = false
                }
            }
        } message: {
            Text(
                "通知対象の路線をすべて解除し、サーバーへAPNs購読情報の削除を要求します。"
            )
        }
    }

    private var explanationSection: some View {
        Section {
            Label(
                "お気に入り路線の変化をお知らせ",
                systemImage: "bell.badge.fill"
            )
            .font(RailFont.extraBold(.headline))
            .foregroundStyle(RailTheme.accent)
            Text(
                "選んだ路線の公式な運転見合わせ・運転再開をお知らせします。利用者からの報告も任意で追加できます。"
            )
            .font(RailFont.regular(.footnote))
            Text(
                "利用者からの報告に基づく「可能性」であり、確定情報ではありません。"
                    + "必ず公式運行情報をご確認ください。"
            )
            .font(RailFont.bold(.footnote))
        }
    }

    private var notificationTypesSection: some View {
        Section("受け取る通知") {
            Toggle("通知をオンにする", isOn: $preferences.notificationSettings.enabled)
                .accessibilityIdentifier("notification-enabled-toggle")
            Toggle("利用者報告も含める", isOn: $preferences.notificationSettings.includeCommunity)
            Text(preferences.notificationSettings.includeCommunity ? "公式情報と利用者の報告を区別して通知します。" : "公式情報のみ通知します。")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("運転見合わせ", isOn: $preferences.notificationSettings.suspension)
            Toggle("運転再開", isOn: $preferences.notificationSettings.resumption)
            Toggle("遅延通知", isOn: $preferences.notificationSettings.delay)
        }
    }

    @ViewBuilder
    private var authorizationSection: some View {
        Section("通知の許可") {
            LabeledContent("現在の設定", value: notificationManager.state.label)

            switch notificationManager.state {
            case .notDetermined:
                Button {
                    Task {
                        await notificationManager.requestAuthorization()
                    }
                } label: {
                    Label("通知を有効にする", systemImage: "bell.fill")
                        .font(RailFont.bold(.body))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(RailTheme.accent)
                .accessibilityIdentifier("notification-authorize-button")
            case .denied:
                Button("iOSの設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .minimumTapTarget()
            case .authorized, .provisional:
                Label("iOSの通知が有効です", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable:
                Label("この環境では通知を利用できません", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
            }

            if let error = notificationManager.registrationError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(RailFont.regular(.footnote))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var routeSection: some View {
        Section {
            Button("お気に入りを通知対象に追加") {
                preferences.addFavoritesToNotifications()
            }
            .minimumTapTarget()

            ForEach(options) { option in
                Toggle(
                    isOn: Binding(
                        get: {
                            preferences.notificationLineIDs.contains(option.id)
                        },
                        set: { _ in
                            preferences.toggleNotification(for: option.id)
                        }
                    )
                ) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: option.color))
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle().stroke(.primary.opacity(0.35), lineWidth: 1)
                            }
                            .accessibilityHidden(true)
                        Text(option.name)
                            .font(RailFont.bold(.body))
                    }
                }
                .tint(RailTheme.accent)
                .accessibilityLabel(
                    "\(option.name)の運行情報通知"
                )
            }
        } header: {
            Text("通知対象の路線")
        } footer: {
            Text(
                "\(preferences.notificationLineIDs.count)路線を登録中。"
                    + "お気に入りと通知対象は別々に保存されます。"
            )
        }
    }

    @ViewBuilder
    private var backendSection: some View {
        Section("配信状態") {
            if notificationManager.backendConfigured {
                Label(
                    "通知サービスに接続できます。",
                    systemImage: "server.rack"
                )
                .foregroundStyle(.green)
            } else {
                Label(
                    "通知サービスは準備中です。路線と通知の種類はこの端末に保存できます。",
                    systemImage: "server.rack"
                )
                .foregroundStyle(.orange)

            }

            Button(role: .destructive) {
                unregisterConfirmationPresented = true
            } label: {
                HStack {
                    if isUnregistering {
                        ProgressView()
                    }
                    Label("サーバーの通知登録を解除", systemImage: "bell.slash.fill")
                        .font(RailFont.bold(.body))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(isUnregistering)
            .accessibilityIdentifier("notification-unregister-button")
        }
    }

    private var privacySection: some View {
        Section("プライバシー") {
            Label(
                "通知配信に必要なAPNs端末トークンと購読路線は、配信サーバーで最終更新から最大180日間保持されます。",
                systemImage: "hand.raised.fill"
            )
            .font(RailFont.regular(.footnote))
            Text(
                "通知登録を解除すると、サーバーへ購読情報の削除を要求します。"
                    + "APNs端末トークンをブラウザ用のWeb Push購読APIへ送信することはありません。"
            )
            .font(RailFont.regular(.caption))
            .foregroundStyle(.secondary)
        }
    }
}
