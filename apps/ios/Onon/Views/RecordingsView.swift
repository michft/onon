import SwiftUI

struct RecordingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.recordings) { recording in
                VStack(alignment: .leading, spacing: 5) {
                    Text(recording.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.headline)
                    Text("\(recording.sampleCount) samples · \(recording.waypointCount) waypoints")
                        .foregroundStyle(.secondary)
                    Label(syncLabel(recording.syncState), systemImage: syncIcon(recording.syncState))
                        .font(.caption)
                        .foregroundStyle(recording.syncState == .failed ? .red : .secondary)
                }
                .padding(.vertical, 3)
            }
            .overlay {
                if model.recordings.isEmpty { ContentUnavailableView("No recordings", systemImage: "figure.walk") }
            }
            .navigationTitle("Saved recordings")
        }
    }

    private func syncLabel(_ state: SyncState) -> String {
        switch state {
        case .local: "Pending"
        case .uploading: "Uploading"
        case .confirmed: "Server confirmed"
        case .failed: "Retry pending"
        }
    }

    private func syncIcon(_ state: SyncState) -> String {
        switch state {
        case .local: "iphone"
        case .uploading: "arrow.up.circle"
        case .confirmed: "checkmark.circle.fill"
        case .failed: "exclamationmark.arrow.triangle.2.circlepath"
        }
    }
}
