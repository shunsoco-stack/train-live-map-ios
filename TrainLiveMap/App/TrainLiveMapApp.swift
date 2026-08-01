import SwiftUI

@main
struct TrainLiveMapApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self)
    private var notificationAppDelegate

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: MainViewModel
    @StateObject private var adManager: AdManager
    @StateObject private var notificationManager: NotificationManager

    init() {
        AppAppearance.configure()
        let configuration = AppConfiguration.current
        let repository: TrainRepository = AppConfiguration.isUITesting
            ? UITestTrainRepository()
            : LiveTrainRepository(configuration: configuration)
        let preferences: UserPreferences
        if AppConfiguration.isUITesting {
            let suiteName = "com.shunsoco.trainlivemap.uitesting"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            preferences = UserPreferences(defaults: defaults)
        } else {
            preferences = UserPreferences()
        }
        _viewModel = StateObject(
            wrappedValue: MainViewModel(
                repository: repository,
                preferences: preferences
            )
        )
        _adManager = StateObject(wrappedValue: AdManager(configuration: configuration))
        _notificationManager = StateObject(wrappedValue: .shared)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if AppConfiguration.isRunningTests {
                    Color.clear
                } else {
                    MainView(
                        viewModel: viewModel,
                        adManager: adManager,
                        notificationManager: notificationManager
                    )
                        .mplusAppTypography()
                        .task {
                            await viewModel.loadCachedDataIfNeeded()
                            // Cache loading may finish after the scene has moved
                            // to the background. Only start network polling while
                            // the app is actually active; onChange below starts it
                            // immediately when the scene becomes active again.
                            if scenePhase == .active {
                                viewModel.activate()
                            }
                            await notificationManager.configure(
                                with: .current
                            )
                            await notificationManager.syncSubscriptions(
                                lineIDs: viewModel.preferences.notificationLineIDs
                            )
                            await adManager.prepare()
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            switch newPhase {
                            case .active:
                                viewModel.activate()
                                Task {
                                    await notificationManager
                                        .refreshAfterBecomingActive(
                                            lineIDs: viewModel.preferences
                                                .notificationLineIDs
                                        )
                                }
                            case .inactive, .background:
                                viewModel.deactivate()
                            @unknown default:
                                viewModel.deactivate()
                            }
                        }
                    }
            }
        }
    }
}
