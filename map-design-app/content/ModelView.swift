import RealityKit
import SwiftUI
import model

struct ModelView: View {
  let model: SceneModel
  let onNewScan: () -> Void

  var body: some View {
    RealityView { content in
      let root = modelEntity(model, opacity: 1)
      let bounds = root.visualBounds(relativeTo: nil)
      let scale = 1 / max(bounds.extents.max(), 0.1)
      root.scale = SIMD3(repeating: scale)
      root.position = -bounds.center * scale
      let pivot = Entity()
      pivot.orientation = simd_quatf(angle: 0.5, axis: SIMD3(1, 0, 0))
      pivot.addChild(root)
      content.add(pivot)
      let light = DirectionalLight()
      light.light.intensity = 4000
      light.look(at: .zero, from: SIMD3(3, 6, 4), relativeTo: nil)
      content.add(light)
    }
    .realityViewCameraControls(.orbit)
    .background(Color(.systemGroupedBackground))
    .ignoresSafeArea()
    .overlay(alignment: .bottom) {
      Button("New scan", action: onNewScan)
        .buttonStyle(.borderedProminent)
    }
  }
}
