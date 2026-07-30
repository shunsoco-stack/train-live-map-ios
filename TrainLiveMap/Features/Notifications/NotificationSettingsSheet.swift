import SwiftUI
import UIKit

struct NotificationSettingsSheet: View {
    let options: [RailwayFilterOption]
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var notificationManager: NotificationManager

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                explanationSection
                authorizationSection
                routeSection
                backendSection
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
    }

    private var explanationSection: some View {
        Section {
            Label(
                "運転見合わせの可能性をお知らせ",
                systemImage: "bell.badge.fill"
            )
            .font(RailFont.extraBold(.headline))
            .foregroundStyle(RailTheme.accent)
            Text(
                "通知対象の路線で、直近5分に異なる利用者から見合わせ報告が3件以上、"
                    + "かつ全報告の60%以上になった場合などに通知します。"
            )
            .font(RailFont.regular(.footnote))
            Text(
                "利用者からの報告に基づく「可能性」であり、確定情報ではありません。"
                    + "必ず公式運行情報をご確認ください。"
            )
            .font(RailFont.bold(.footnote))
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
                        await sync()
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
                Task { await sync() }
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
                            Task { await sync() }
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
                    "\(option.name)の運転見合わせ可能性通知"
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
                    "APNs端末登録バックエンドが設定されています。",
                    systemImage: "server.rack"
                )
                .foregroundStyle(.green)
            } else {
                Label(
                    "APNs端末登録先が未設定のため、通知許可と路線設定のみ保存されます。",
                    systemImage: "server.rack"
                )
                .foregroundStyle(.orange)
                Text(
                    "App Store公開前に、端末トークン・購読路線を受け付ける"
                        + "APNsバックエンドURLを設定してください。"
                )
                .font(RailFont.regular(.footnote))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func sync() async {
        await notificationManager.syncSubscriptions(
            lineIDs: preferences.notificationLineIDs
        )
    }
}
