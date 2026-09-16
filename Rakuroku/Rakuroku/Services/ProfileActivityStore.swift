import Foundation
import Observation

@MainActor @Observable
final class ProfileActivityStore {
    private(set) var activities: [ListActivity] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private var requestID = UUID()

    func invalidate() {
        requestID = UUID()
        isLoading = false
    }

    func reset() {
        invalidate()
        activities = []
        hasLoaded = false
        error = nil
    }

    func load(
        isCurrent: () -> Bool,
        using loader: () async throws -> [ListActivity]
    ) async {
        guard isCurrent() else { return }
        let id = UUID()
        requestID = id
        isLoading = true
        error = nil
        defer {
            if requestID == id { isLoading = false }
        }
        do {
            let result = try await loader()
            try Task.checkCancellation()
            guard requestID == id, isCurrent() else { return }
            activities = result
            hasLoaded = true
        } catch where error.isCancellation {
        } catch {
            guard requestID == id, isCurrent() else { return }
            self.error = error.localizedDescription
        }
    }
}
