import FirebaseCore
import MetricKit
import OSLog
import UIKit
import UserNotifications

extension Notification.Name {
    static let stylezamOpenScan = Notification.Name("stylezam.open-scan")
}

final class StylezamAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil,
           let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path),
           options.bundleID == Bundle.main.bundleIdentifier
        {
            FirebaseApp.configure(options: options)
        }
        StylezamPerformanceDiagnostics.shared.start()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let scanID = userInfo["scanID"] as? String {
            StylezamShared.defaults.set(scanID, forKey: StylezamShared.pendingScanIDKey)
            await MainActor.run {
                NotificationCenter.default.post(name: .stylezamOpenScan, object: scanID)
            }
        }
    }
}

enum StylezamPerformanceTrace {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.stylezam.app",
        category: "Performance"
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

}

/// Collects Apple's device-produced launch, hang, memory, CPU, disk, and crash
/// diagnostics locally. MetricKit never receives garment images from Stylezam;
/// its payloads are bounded JSON files that can be retrieved from a test device.
final class StylezamPerformanceDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = StylezamPerformanceDiagnostics()

    private let queue = DispatchQueue(label: "com.stylezam.performance-metrics", qos: .utility)
    private var started = false

    struct Snapshot: Sendable {
        let thermalState: String
        let lowPowerMode: Bool
        let payloadCount: Int
        let newestPayloadDate: Date?
    }

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(memoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "metric")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "diagnostic")
    }

    func snapshot() async -> Snapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                let files = Self.metricFiles()
                let newest = files.compactMap {
                    try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate
                }.max()
                continuation.resume(
                    returning: Snapshot(
                        thermalState: Self.thermalStateName(ProcessInfo.processInfo.thermalState),
                        lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                        payloadCount: files.count,
                        newestPayloadDate: newest
                    )
                )
            }
        }
    }

    @objc private func thermalStateChanged() {
        os_log(
            "Thermal state changed to %{public}d",
            log: OSLog(subsystem: "com.stylezam.app", category: "Performance"),
            type: .info,
            ProcessInfo.processInfo.thermalState.rawValue
        )
    }

    @objc private func memoryWarning() {
        os_log(
            "Memory warning received",
            log: OSLog(subsystem: "com.stylezam.app", category: "Performance"),
            type: .fault
        )
    }

    private func persist(_ payloads: [Data], prefix: String) {
        guard !payloads.isEmpty else { return }
        queue.async {
            let root = Self.metricsDirectory()
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for payload in payloads {
                let filename = "\(prefix)-\(UUID().uuidString).json"
                try? payload.write(to: root.appending(path: filename), options: .atomic)
            }
            let files = ((try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []).sorted {
                let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                return (left ?? .distantPast) > (right ?? .distantPast)
            }
            for stale in files.dropFirst(12) {
                try? FileManager.default.removeItem(at: stale)
            }
        }
    }

    private static func metricsDirectory() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appending(path: "Stylezam", directoryHint: .isDirectory)
            .appending(path: "PerformanceMetrics", directoryHint: .isDirectory)
    }

    private static func metricFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: metricsDirectory(),
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
    }

    private static func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
