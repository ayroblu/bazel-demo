import SwiftData
import SwiftUI

struct NotifAppsView: View {
  @StateObject var vm: MainVM
  @Query(sort: \NotifAppsModel.name) var apps: [NotifAppsModel]
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    List {
      ForEach(apps) { app in
        Toggle(isOn: Bindable(app).enabled) {
          Text(app.name)
        }
      }
    }
    .navigationTitle("Notification Apps")
  }
}
