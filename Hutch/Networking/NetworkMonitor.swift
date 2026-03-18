import Foundation
import Network

/// Observes network connectivity using `NWPathMonitor`.
/// Shared singleton injected into the environment.
@Observable
@MainActor
final class NetworkMonitor {

    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType: Sendable {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "net.cleberg.Hutch.NetworkMonitor")

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.connectionType = self.resolveConnectionType(path)
            }
        }
        monitor.start(queue: queue)
    }

    private nonisolated func resolveConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return .unknown
    }

    deinit {
        monitor.cancel()
    }
}
