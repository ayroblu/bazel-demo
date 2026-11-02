import SwiftUI
import feed

struct FeedView: View {
  let title: String
  @State private var model: FeedModel
  @Environment(\.scenePhase) private var scenePhase

  init(title: String, source: FeedSource) {
    self.title = title
    _model = State(initialValue: FeedModel(source: source))
  }

  var body: some View {
    NavigationStack {
      List {
        if model.error != nil, let fetchedAt = model.fetchedAt {
          Text("Offline · updated \(fetchedAt.formatted(.relative(presentation: .named)))")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        ForEach(model.items) { item in
          FeedRow(item: item)
        }
      }
      .listStyle(.plain)
      .overlay {
        if model.items.isEmpty {
          EmptyFeedView(model: model)
        }
      }
      .navigationTitle(title)
      .refreshable { await model.refresh() }
      .task { await model.load() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          Task { await model.refresh() }
        }
      }
    }
  }
}

private struct EmptyFeedView: View {
  let model: FeedModel

  var body: some View {
    if let error = model.error {
      ContentUnavailableView(
        "Couldn't load the feed", systemImage: "wifi.slash",
        description: Text(error.localizedDescription))
    } else if model.fetchedAt == nil {
      ProgressView()
    } else {
      ContentUnavailableView(
        "No stories yet", systemImage: "newspaper",
        description: Text("Pull to refresh"))
    }
  }
}
