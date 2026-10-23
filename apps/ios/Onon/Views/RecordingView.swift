import CoreLocation
import SwiftUI

struct RecordingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmFinish = false
    @State private var recenterRequest = 0
    @AppStorage("showCaptureDiagnostics") private var showDiagnostics = false
    @AppStorage(WaypointFixAge.key) private var waypointFixAge = WaypointFixAge.defaultValue

    var body: some View {
        NavigationStack {
            Group {
                if let styleURL = BundledMap.cachedStyleURL(dark: colorScheme == .dark) {
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
                PermissionHint(recorder: model.locationRecorder)
                if showDiagnostics {
                    CaptureDiagnostics(recorder: model.locationRecorder)
                }
            }
            Spacer()
            LocationFixIndicator(recorder: model.locationRecorder)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        // Hidden field-test aid: long-press the status card to show or hide capture diagnostics.
        .onLongPressGesture { showDiagnostics.toggle() }
        .accessibilityAction(named: showDiagnostics ? "Hide capture diagnostics" : "Show capture diagnostics") {
            showDiagnostics.toggle()
        }
    }

    @ViewBuilder private var controls: some View {
        if model.finishNeedsRetry {
            control("Retry finish", icon: "arrow.clockwise") { Task { await model.finish() } }
                .tint(.red)
                .controlSize(.large)
        } else if let state = model.currentRecording?.summary.state {
            HStack(spacing: 12) {
                if state == .active && model.captureFailure == nil {
                    control("Pause", icon: "pause.fill") { Task { await model.pause() } }
                    // Tap adds a waypoint; long-press chooses how old its location fix may be.
                    Menu {
                        Picker("Use a location fix up to", selection: $waypointFixAge) {
                            ForEach(WaypointFixAge.options, id: \.self) { Text(WaypointFixAge.label($0)).tag($0) }
                        }
                    } label: {
                        Label("Waypoint", systemImage: "dot.circle").frame(maxWidth: .infinity)
                    } primaryAction: {
                        Task { await model.addWaypoint() }
                    }
                    .buttonStyle(.borderedProminent)
                    .labelStyle(.titleOnly)
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
        if model.finishNeedsRetry { return "Capture stopped — finish needs retry" }
        if model.captureFailure != nil { return "Capture stopped — save failed" }
        return switch model.currentRecording?.summary.state {
        case .active: "Recording"
        case .paused: "Paused"
        case .finished, .none: "Ready"
        }
    }

    private var statusColor: Color {
        if model.captureFailure != nil || model.finishNeedsRetry { return .red }
        return switch model.currentRecording?.summary.state {
        case .active: .red
        case .paused: .orange
        case .finished, .none: .secondary
        }
    }
}

/// Observes the recorder directly: SwiftUI does not forward changes from objects nested in `AppModel`.
private struct PermissionHint: View {
    @ObservedObject var recorder: LocationRecorder

    var body: some View {
        if recorder.authorizationStatus == .authorizedWhenInUse {
            Text("Allow Always location access for lock-screen recording")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let error = recorder.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

private struct LocationFixIndicator: View {
    @ObservedObject var recorder: LocationRecorder

    var body: some View {
        if recorder.lastLocation != nil {
            Image(systemName: "location.fill").foregroundStyle(.green)
        }
    }
}

/// What Onon did with the fixes iOS delivered: rejected counts point at the accuracy filter,
/// a growing "last fix" age while walking points at iOS suspending delivery.
private struct CaptureDiagnostics: View {
    @ObservedObject var recorder: LocationRecorder

    var body: some View {
        let stats = recorder.stats
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text("Fixes \(stats.delivered) · kept \(stats.accepted) · weak \(stats.rejectedInaccurate) · stale \(stats.rejectedStale)")
                Text(deliveryLine(stats, now: context.date))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func deliveryLine(_ stats: CaptureStats, now: Date) -> String {
        guard let last = stats.lastDeliveredAt else {
            return recorder.isCapturing ? "Waiting for first fix" : "Not capturing"
        }
        let accuracy = stats.lastAccuracy.map { $0 >= 0 ? "±\(Int($0.rounded())) m" : "no accuracy" } ?? "–"
        return "Last fix \(Int(now.timeIntervalSince(last)))s ago, \(accuracy) · longest gap \(Int(stats.longestGap))s"
    }
}
