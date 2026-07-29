import SwiftUI

@main
struct TrainLiveMapApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: MainViewModel
    @StateObject private var adManager: AdManager

    init() {
        let configuration = AppConfiguration.current
        _viewModel = StateObject(wrappedValue: MainViewModel(configuration: configuration))
        _adManager = StateObject(wrappedValue: AdManager(configuration: configuration))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if AppConfiguration.isRunningTests {
                    Color.clear
                } else {
                    MainView(viewModel: viewModel, adManager: adManager)
                        .task {
                            await viewModel.loadCachedDataIfNeeded()
                            viewModel.activate()
                            await adManager.prepare()
                        }
                        .onChange(of: scenePhase) { _, newPhase in
                            switch newPhase {
                            case .active:
                                viewModel.activate()
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
