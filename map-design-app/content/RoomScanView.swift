import RoomPlan
import SwiftUI
import capture
import model

struct RoomScanView: View {
  let onFinish: (SceneModel?) -> Void
  @State private var scanner = RoomScanner()

  var body: some View {
    RoomCaptureRepresentable(scanner: scanner)
      .ignoresSafeArea()
      .overlay(alignment: .bottom) {
        if scanner.isProcessing {
          ProgressView("Building model…")
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        } else {
          Button("Done") { scanner.stop() }
            .buttonStyle(.borderedProminent)
        }
      }
      .alert(
        "Couldn't build the room model", isPresented: .constant(scanner.errorMessage != nil)
      ) {
        Button("OK") { onFinish(nil) }
      } message: {
        Text(scanner.errorMessage ?? "")
      }
      .onChange(of: scanner.isFinished) {
        onFinish(scanner.model)
      }
  }
}

@Observable final class RoomScanner: nonisolated RoomCaptureSessionDelegate {
  var isProcessing = false
  var isFinished = false
  var errorMessage: String?
  @ObservationIgnored var model: SceneModel?
  @ObservationIgnored private var session: RoomCaptureSession?

  func start(_ session: RoomCaptureSession) {
    self.session = session
    session.delegate = self
    session.run(configuration: RoomCaptureSession.Configuration())
  }

  func stop() {
    isProcessing = true
    session?.stop()
  }

  nonisolated func captureSession(
    _ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?
  ) {
    Task { @MainActor in
      await build(data, error: error)
    }
  }

  private func build(_ data: CapturedRoomData, error: (any Error)?) async {
    do {
      if let error { throw error }
      let room = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
      model = SceneModel(room: room)
      isFinished = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct RoomCaptureRepresentable: UIViewRepresentable {
  let scanner: RoomScanner

  func makeUIView(context: Context) -> RoomCaptureView {
    let view = RoomCaptureView(frame: .zero)
    scanner.start(view.captureSession)
    return view
  }

  func updateUIView(_ view: RoomCaptureView, context: Context) {}
}
