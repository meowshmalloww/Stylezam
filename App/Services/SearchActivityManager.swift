@preconcurrency import ActivityKit
import Foundation

@MainActor
final class SearchActivityManager {
    private var activity: Activity<StylezamSearchActivityAttributes>?

    func start(for job: SearchJobDTO) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
        }
        let attributes = StylezamSearchActivityAttributes(
            searchID: job.id,
            query: job.query
        )
        let state = contentState(for: job)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    func update(with job: SearchJobDTO) async {
        guard let activity else { return }
        let content = ActivityContent(state: contentState(for: job), staleDate: nil)
        if job.status.isTerminal {
            await activity.end(
                content,
                dismissalPolicy: .after(.now.addingTimeInterval(45))
            )
            self.activity = nil
        } else {
            await activity.update(content)
        }
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    private func contentState(
        for job: SearchJobDTO
    ) -> StylezamSearchActivityAttributes.ContentState {
        .init(
            phase: job.phase.title,
            progress: job.progress,
            resultCount: job.resultCount,
            isComplete: job.status == .completed,
            failed: job.status == .failed
        )
    }
}
