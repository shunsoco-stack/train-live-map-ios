import Foundation
import Network

enum NetworkConnectivityStatus: Equatable, Sendable {
    case unknown
    case online
    case offline
}

protocol NetworkConnectivityMonitoring: Sendable {
    var currentStatus: NetworkConnectivityStatus { get }
    func statusUpdates() -> AsyncStream<NetworkConnectivityStatus>
}

struct AssumedOnlineConnectivityMonitor: NetworkConnectivityMonitoring {
    let currentStatus = NetworkConnectivityStatus.online

    func statusUpdates() -> AsyncStream<NetworkConnectivityStatus> {
        AsyncStream { continuation in
            continuation.yield(.online)
            continuation.finish()
        }
    }
}

final class NWPathConnectivityMonitor: NetworkConnectivityMonitoring,
    @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(
        label: "com.shunsoco.trainlivemap.network-monitor"
    )
    private let lock = NSLock()
    private var status: NetworkConnectivityStatus = .unknown
    private var continuations: [
        UUID: AsyncStream<NetworkConnectivityStatus>.Continuation
    ] = [:]

    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            self?.publish(path.status == .satisfied ? .online : .offline)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
        lock.lock()
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        activeContinuations.forEach { $0.finish() }
    }

    var currentStatus: NetworkConnectivityStatus {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    func statusUpdates() -> AsyncStream<NetworkConnectivityStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
            lock.lock()
            continuations[id] = continuation
            // Yield while registration is serialized so a newer path update
            // can never be followed by an older initial status.
            continuation.yield(status)
            lock.unlock()
        }
    }

    private func publish(_ newStatus: NetworkConnectivityStatus) {
        lock.lock()
        guard status != newStatus else {
            lock.unlock()
            return
        }
        status = newStatus
        let activeContinuations = Array(continuations.values)
        lock.unlock()
        activeContinuations.forEach { $0.yield(newStatus) }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
