@preconcurrency import ActivityKit
import Foundation

@MainActor
final class CaptureActivityManager {
    private var activity: Activity<StylezamCaptureActivityAttributes>?
    private var activeCaptureID: String?

    func start(id: String, source: String, phase: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        activeCaptureID = nil
        do {
            activity = try Activity.request(
                attributes: StylezamCaptureActivityAttributes(
                    captureID: id,
                    source: source
                ),
                content: ActivityContent(
                    state: .init(
                        phase: phase,
                        itemCount: 0,
                        isComplete: false,
                        failed: false
                    ),
                    staleDate: .now.addingTimeInterval(90)
                )
            )
            activeCaptureID = id
        } catch {
            activity = nil
            activeCaptureID = nil
        }
    }

    func update(
        captureID: String? = nil,
        phase: String,
        itemCount: Int,
        isComplete: Bool,
        failed: Bool
    ) async {
        guard let activity, matches(captureID) else { return }
        await activity.update(
            ActivityContent(
                state: .init(
                    phase: phase,
                    itemCount: itemCount,
                    isComplete: isComplete,
                    failed: failed
                ),
                staleDate: .now.addingTimeInterval(90)
            )
        )
    }

    func finish(
        captureID: String? = nil,
        itemCount: Int,
        failed: Bool
    ) async {
        guard let activity, matches(captureID) else { return }
        let phase: String
        if failed {
            phase = "Capture needs attention"
        } else if itemCount == 0 {
            phase = "Capture saved"
        } else if itemCount == 1 {
            phase = "1 piece ready"
        } else {
            phase = "\(itemCount) pieces ready"
        }
        await activity.end(
            ActivityContent(
                state: .init(
                    phase: phase,
                    itemCount: itemCount,
                    isComplete: !failed,
                    failed: failed
                ),
                staleDate: nil
            ),
            dismissalPolicy: .after(.now.addingTimeInterval(45))
        )
        self.activity = nil
        activeCaptureID = nil
    }

    func end(
        captureID: String? = nil,
        phase: String,
        failed: Bool = false
    ) async {
        guard let activity, matches(captureID) else { return }
        await activity.end(
            ActivityContent(
                state: .init(
                    phase: phase,
                    itemCount: 0,
                    isComplete: !failed,
                    failed: failed
                ),
                staleDate: nil
            ),
            dismissalPolicy: .after(.now.addingTimeInterval(20))
        )
        self.activity = nil
        activeCaptureID = nil
    }

    private func matches(_ captureID: String?) -> Bool {
        captureID == nil || captureID == activeCaptureID
    }
}
