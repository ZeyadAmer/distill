import Foundation
import OSLog
import MetricKit

/// Collects crash diagnostics via MetricKit and forwards them to Supabase.
///
/// MetricKit delivers a crashed run's diagnostics on the *next* launch, so
/// reports arrive one session late — that's how the framework works, not a bug.
/// Best-effort and silent: failures never surface. Payloads contain call stacks
/// and OS/app metadata only — never clipboard content. Reuses the same
/// anonymous install id as `DeviceTracker` (no PII).
final class CrashReporter: NSObject, MXMetricManagerSubscriber {

    static let shared = CrashReporter()

    private let logger = Logger(subsystem: "com.zeyadamer.hotstash", category: "CrashReporter")

    /// Subscribes to MetricKit. Call once at launch.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // Required by MXMetricManagerSubscriber; we only care about diagnostics.
    func didReceive(_ payloads: [MXMetricPayload]) {}

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { $0.crashDiagnostics ?? [] }
        guard !crashes.isEmpty else { return }
        logger.log("Received \(crashes.count, privacy: .public) crash diagnostic(s)")
        for crash in crashes { send(crash) }
    }

    // MARK: - Upload

    private func send(_ crash: MXCrashDiagnostic) {
        guard
            let config = SupabaseConfig.current,
            let url = URL(string: config.url.absoluteString + "/rest/v1/rpc/record_crash"),
            let payload = try? JSONSerialization.jsonObject(with: crash.jsonRepresentation())
        else { return }

        let meta = crash.metaData
        let body: [String: Any] = [
            "p_device_id":          DeviceTracker.installID,
            "p_platform":           "macos",
            "p_payload":            payload,
            "p_app_version":        crash.applicationVersion,
            "p_os_version":         meta.osVersion,
            "p_device_model":       meta.deviceType,
            "p_exception_type":     crash.exceptionType.map { "\($0)" } as Any,
            "p_signal":             crash.signal.map { "\($0)" } as Any,
            "p_termination_reason": crash.terminationReason as Any,
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody

        Task.detached {
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}
