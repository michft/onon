import CoreLocation
import SwiftUI

struct RecordingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmFinish = false
    @State private var recenterRequest = 0

    var body: some View {
        NavigationStack {
            Group {
                if let styleURL = BundledMap.styleURL(dark: colorScheme == .dark) {
                    MapCanvas(
                        styleURL: styleURL,
                        recording: model.currentRecording,
                        visibleBounds: .constant(nil),
                        initialZoomLevel: 16,
                        recenterRequest: recenterRequest
                    )
                    .overlay(alignment: .topLeading) {
                        Button { recenterRequest += 1 } label: {
                            Image(systemName: "location.fill")
                                .frame(width: 44, height: 44)
                        }
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel("Follow my location")
                        .padding(12)
                    }
                } else {
                    ContentUnavailableView(
                        "Offline map unavailable",
                        systemImage: "map",
                        description: Text("This build could not load its Sydney map. Recording remains available.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    statusCard
                    controls
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Trail recorder")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Finish this recording?", isPresented: $confirmFinish) {
                Button("Finish recording", role: .destructive) { Task { await model.finish() } }
                Button("Keep recording", role: .cancel) {}
            } message: {
                Text("Finishing is permanent. The raw recording stays on this phone after sync.")
            }
        }
    }

    private var statusCard: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(statusText).font(.headline)
                if let summary = model.currentRecording?.summary {
                    Text("\(summary.sampleCount) samples · \(summary.waypointCount) waypoints")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.locationRecorder.authorizationStatus == .authorizedWhenInUse {
                    Text("Allow Always location access for lock-screen recording")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if model.locationRecorder.lastLocation != nil {
                Image(systemName: "location.fill").foregroundStyle(.green)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var controls: some View {
        if let state = model.currentRecording?.summary.state {
            HStack(spacing: 12) {
                if state == .active {
                    control("Pause", icon: "pause.fill") { Task { await model.pause() } }
                    control("Waypoint", icon: "dot.circle") { Task { await model.addWaypoint() } }
                } else {
                    control("Resume", icon: "play.fill") { Task { await model.resume() } }
                }
                Button(role: .destructive) { confirmFinish = true } label: {
                    Label("Finish", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .labelStyle(.titleOnly)
            }
            .controlSize(.large)
        } else {
            Button { Task { await model.start() } } label: {
                Label("Start recording", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func control(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent)
            .labelStyle(.titleOnly)
    }

    private var statusText: String {
        switch model.currentRecording?.summary.state {
        case .active: "Recording"
        case .paused: "Paused"
        case .finished, .none: "Ready"
        }
    }

    private var statusColor: Color {
        switch model.currentRecording?.summary.state {
        case .active: .red
        case .paused: .orange
        case .finished, .none: .secondary
        }
    }
}
