import ARKit
import Synchronization
import reconstruction

public final class SiteScanner: NSObject, ARSessionDelegate, Sendable {
  public let reconstructor = Reconstructor()
  private let state = Mutex(State())

  public static var isSupported: Bool {
    ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
  }

  public func run(_ session: ARSession) {
    let configuration = ARWorldTrackingConfiguration()
    configuration.frameSemantics = .sceneDepth
    if ARWorldTrackingConfiguration.supportsFrameSemantics([.sceneDepth, .personSegmentation]) {
      configuration.frameSemantics.insert(.personSegmentation)
    }
    session.delegate = self
    session.run(configuration)
  }

  public func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard case .normal = frame.camera.trackingState else { return }
    let isAccepted = state.withLock { state in
      guard !state.isBusy, frame.timestamp - state.lastTimestamp >= frameInterval else {
        return false
      }
      state.isBusy = true
      state.lastTimestamp = frame.timestamp
      return true
    }
    guard isAccepted else { return }
    let depthFrame = DepthFrame(frame)
    Task {
      if let depthFrame {
        await reconstructor.integrate(depthFrame)
      }
      state.withLock { $0.isBusy = false }
    }
  }
}

private struct State {
  var isBusy = false
  var lastTimestamp: TimeInterval = 0
}

extension DepthFrame {
  fileprivate init?(_ frame: ARFrame) {
    guard let sceneDepth = frame.sceneDepth, let confidenceMap = sceneDepth.confidenceMap else {
      return nil
    }
    let (width, height, rawDepth) = pixels(sceneDepth.depthMap, as: Float32.self)
    let (_, _, confidence) = pixels(confidenceMap, as: UInt8.self)
    let depth = zip(rawDepth, confidence).map {
      $1 >= UInt8(ARConfidenceLevel.medium.rawValue) ? $0 : 0
    }
    var isSurface = [Bool](repeating: true, count: width * height)
    if let segmentation = frame.segmentationBuffer {
      let (maskWidth, maskHeight, mask) = pixels(segmentation, as: UInt8.self)
      let person = ARFrame.SegmentationClass.person.rawValue
      for v in 0..<height {
        for u in 0..<width {
          let mu = u * maskWidth / width
          let mv = v * maskHeight / height
          let isPerson = (max(mv - 1, 0)...min(mv + 1, maskHeight - 1)).contains { y in
            (max(mu - 1, 0)...min(mu + 1, maskWidth - 1)).contains { mask[y * maskWidth + $0] == person }
          }
          if isPerson {
            isSurface[v * width + u] = false
          }
        }
      }
    }
    let scale = Float(width) / Float(frame.camera.imageResolution.width)
    var intrinsics = frame.camera.intrinsics
    intrinsics[0][0] *= scale
    intrinsics[1][1] *= scale
    intrinsics[2][0] *= scale
    intrinsics[2][1] *= scale
    self.init(
      width: width, height: height, depth: depth, isSurface: isSurface, intrinsics: intrinsics,
      cameraToWorld: frame.camera.transform, timestamp: frame.timestamp)
  }
}

private func pixels<T>(_ buffer: CVPixelBuffer, as type: T.Type) -> (Int, Int, [T]) {
  CVPixelBufferLockBaseAddress(buffer, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
  let width = CVPixelBufferGetWidth(buffer)
  let height = CVPixelBufferGetHeight(buffer)
  let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
  let base = CVPixelBufferGetBaseAddress(buffer)!
  var values: [T] = []
  values.reserveCapacity(width * height)
  for row in 0..<height {
    let pointer = (base + row * bytesPerRow).assumingMemoryBound(to: T.self)
    values.append(contentsOf: UnsafeBufferPointer(start: pointer, count: width))
  }
  return (width, height, values)
}

private let frameInterval: TimeInterval = 0.1
