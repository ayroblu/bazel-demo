import SwiftUI
import tfl

struct RoutePickerView: View {
  let lines: [BusLine]
  let nearbyLines: [BusLine]
  let onSelect: (String) -> Void
  @State private var query = ""

  var body: some View {
    NavigationStack {
      List {
        if query.isEmpty, !nearbyLines.isEmpty {
          Section("Nearby") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], alignment: .leading) {
              ForEach(nearbyLines) { line in
                Button {
                  onSelect(line.id)
                } label: {
                  RouteBadge(name: line.name)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        Section("All routes") {
          ForEach(filteredLines) { line in
            Button {
              onSelect(line.id)
            } label: {
              RouteBadge(name: line.name)
            }
          }
        }
      }
      .overlay {
        if lines.isEmpty {
          ProgressView()
        }
      }
      .searchable(
        text: $query, placement: .navigationBarDrawer(displayMode: .always),
        prompt: "Route number"
      )
      .onSubmit(of: .search) {
        if let line = filteredLines.first {
          onSelect(line.id)
        }
      }
      .navigationTitle("Routes")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var filteredLines: [BusLine] {
    let query = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return lines }
    return lines.filter { $0.name.lowercased().hasPrefix(query) }
  }
}
