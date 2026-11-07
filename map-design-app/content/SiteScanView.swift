import RealityKit
import SwiftUI
import capture
import model

struct SiteScanView: View {
  let onFinish: (SceneModel) -> Void
  @State private var scan = SiteScan()

  var body: some View {
    SiteARView(scanner: scan.scanner, model: scan.model)
      .ignoresSafeArea()
      .overlay(alignment: .bottom) {
        VStack(spacing: 12) {
          Text("\(scan.model.elements.count) elements from \(scan.voxelCount) voxels")
            .font(.footnote)
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          if scan.isFinishing {
            ProgressView("Building model…")
          } else {
            Button("Done") {
              Task { onFinish(await scan.finish()) }
            }
            .buttonStyle(.borderedProminent)
          }
        }
      }
      .task {
        await scan.refresh()
      }
  }
}

@Observable final class SiteScan {
  let scanner = SiteScanner()
  var model = SceneModel()
  var voxelCount = 0
  var isFinishing = false

  func refresh() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(2))
      model = await scanner.reconstructor.model()
      voxelCount = await scanner.reconstructor.voxelCount
    }
  }

  func finish() async -> SceneModel {
    isFinishing = true
    return await scanner.reconstructor.model()
  }
}

struct SiteARView: UIViewRepresentable {
  let scanner: SiteScanner
  let model: SceneModel

  func makeUIView(context: Context) -> ARView {
    let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    scanner.run(view.session)
    view.scene.addAnchor(context.coordinator.anchor)
    return view
  }

  func updateUIView(_ view: ARView, context: Context) {
    context.coordinator.anchor.children.removeAll()
    context.coordinator.anchor.addChild(modelEntity(model, opacity: 0.6))
  }

  static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
    view.session.pause()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class Coordinator {
    let anchor = AnchorEntity(world: .zero)
  }
}
