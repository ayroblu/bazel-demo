import SwiftUI
import tfl

struct StopArrivalsView: View {
  let stop: BusStop
  let onSelectArrival: (Arrival) -> Void
  let onSelectLine: (String) -> Void
  @State private var arrivals: [Arrival]?
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        if let towards = stop.towards, !towards.isEmpty {
          Section {
            Label("Towards \(towards)", systemImage: "arrow.forward")
          }
        }
        Section("Live arrivals") {
          if let errorMessage {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
          if let arrivals {
            if arrivals.isEmpty {
              Text("No buses due")
                .foregroundStyle(.secondary)
            }
            ForEach(arrivals) { arrival in
              Button {
                onSelectArrival(arrival)
              } label: {
                ArrivalRow(arrival: arrival)
              }
              .tint(.primary)
            }
          } else if errorMessage == nil {
            ProgressView()
          }
        }
        if !stop.lineIds.isEmpty {
          Section("Routes from this stop") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], alignment: .leading) {
              ForEach(stop.lineIds, id: \.self) { lineId in
                Button {
                  onSelectLine(lineId)
                } label: {
                  RouteBadge(name: lineId.uppercased())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
      .navigationTitle(stopTitle)
      .navigationBarTitleDisplayMode(.inline)
    }
    .task(id: stop.id) {
      while !Task.isCancelled {
        do {
          arrivals = try await getStopArrivals(stopId: stop.id)
          errorMessage = nil
        } catch {
          guard !Task.isCancelled else { return }
          errorMessage = "Couldn't load arrivals: \(error.localizedDescription)"
        }
        try? await Task.sleep(for: .seconds(30))
      }
    }
  }

  private var stopTitle: String {
    guard let letter = stop.letter, !letter.isEmpty else { return stop.name }
    return "\(stop.name) (\(letter))"
  }
}

struct ArrivalRow: View {
  let arrival: Arrival

  var body: some View {
    TimelineView(.periodic(from: .now, by: 10)) { context in
      HStack(spacing: 12) {
        RouteBadge(name: arrival.lineName)
        Text(arrival.destination)
          .lineLimit(1)
        Spacer()
        Text(countdown(to: arrival.expectedArrival, now: context.date))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }
}
