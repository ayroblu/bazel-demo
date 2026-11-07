import RoomPlan
import SwiftUI
import capture
import model

public struct ContentView: View {
  @State private var screen = Screen.start

  public init() {}

  public var body: some View {
    switch screen {
    case .start:
      StartView { screen = $0 }
    case .room:
      RoomScanView { screen = $0.map(Screen.model) ?? .start }
    case .site:
      SiteScanView { screen = .model($0) }
    case .model(let model):
      ModelView(model: model) { screen = .start }
    }
  }
}

enum Screen {
  case start
  case room
  case site
  case model(SceneModel)
}

struct StartView: View {
  let onSelect: (Screen) -> Void

  var body: some View {
    VStack(spacing: 20) {
      Text("Map Design")
        .font(.largeTitle.bold())
      Text(
        "Scan with the LiDAR camera to build a model of floors, walls, objects and trees. People and things that move are left out."
      )
      .multilineTextAlignment(.center)
      Button("Scan a room") { onSelect(.room) }
        .buttonStyle(.borderedProminent)
        .disabled(!RoomCaptureSession.isSupported)
      Button("Scan a site (indoor or outdoor)") { onSelect(.site) }
        .buttonStyle(.borderedProminent)
        .disabled(!SiteScanner.isSupported)
      if !SiteScanner.isSupported {
        Text("This device has no LiDAR scanner.")
          .foregroundStyle(.red)
      }
    }
    .padding()
  }
}
