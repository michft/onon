import SwiftUI

struct OfflineAreasView: View {
    @EnvironmentObject private var model: AppModel
    @State private var visibleBounds: OfflineBounds?
    @State private var detailName = "Field area"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapCanvas(styleURL: model.offlineMaps.styleURL, recording: nil, visibleBounds: $visibleBounds)
                    .frame(minHeight: 260)
                List {
                    Section("Download current map view") {
                        TextField("Area name", text: $detailName)
                        if let bounds = visibleBounds {
                            Text(estimate(bounds)).font(.caption).foregroundStyle(.secondary)
                            Button("Download detailed area") {
                                model.offlineMaps.downloadDetail(name: detailName, bounds: bounds)
                            }
                        }
                        Button("Download Sydney overview") { model.offlineMaps.downloadOverview() }
                            .disabled(model.offlineMaps.serviceBounds == nil)
                    }
                    Section("Downloaded areas") {
                        ForEach(model.offlineMaps.areas) { area in
                            OfflineAreaRow(area: area)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Offline maps")
        }
    }

    private func estimate(_ bounds: OfflineBounds) -> String {
        let bytes = model.offlineMaps.estimatedBytes(
            bounds: bounds,
            minimumZoom: max(10, model.offlineMaps.overviewMaxZoom - 1),
            maximumZoom: model.offlineMaps.detailMaxZoom
        )
        return "Estimated \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)); actual size varies."
    }
}

private struct OfflineAreaRow: View {
    @EnvironmentObject private var model: AppModel
    let area: OfflineArea

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(area.name).font(.headline)
                Spacer()
                Text(area.state.rawValue.capitalized).foregroundStyle(.secondary)
            }
            ProgressView(value: area.progress)
            Text(ByteCountFormatter.string(fromByteCount: Int64(area.completedBytes), countStyle: .file))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if area.state == .downloading {
                    Button("Pause") { model.offlineMaps.pause(area.id) }
                } else if area.state != .complete {
                    Button("Resume") { model.offlineMaps.resume(area.id) }
                }
                Spacer()
                Button("Remove", role: .destructive) { model.offlineMaps.remove(area.id) }
            }
            if let error = area.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
