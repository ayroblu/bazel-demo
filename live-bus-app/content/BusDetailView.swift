import SwiftUI
import tfl

struct BusDetailView: View {
  let track: VehicleTrack?

  var body: some View {
    NavigationStack {
      if let track {
        TimelineView(.periodic(from: .now, by: 10)) { context in
          List {
            Section {
              LabeledContent("Towards", value: track.destination)
              LabeledContent("Registration", value: track.id)
            }
            Section("Stops") {
              ForEach(track.stops) { stop in
                HStack {
                  Text(stop.stop.name)
                  Spacer()
                  Text(stopStatus(stop, now: context.date))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        .navigationTitle("Route \(track.lineName)")
        .navigationBarTitleDisplayMode(.inline)
      } else {
        ContentUnavailableView(
          "Bus not found", systemImage: "bus",
          description: Text("This bus no longer has live predictions"))
      }
    }
  }
}

private func stopStatus(_ stop: TrackStop, now: Date) -> String {
  if stop.isEstimated || stop.arrival < now.addingTimeInterval(-30) {
    return "Left"
  }
  return countdown(to: stop.arrival, now: now)
}
