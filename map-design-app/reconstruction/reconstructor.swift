import model
import simd

public struct DepthFrame: Sendable {
  public var width: Int
  public var height: Int
  public var depth: [Float]
  public var isSurface: [Bool]
  public var intrinsics: simd_float3x3
  public var cameraToWorld: simd_float4x4
  public var timestamp: Double

  public init(
    width: Int, height: Int, depth: [Float], isSurface: [Bool], intrinsics: simd_float3x3,
    cameraToWorld: simd_float4x4, timestamp: Double
  ) {
    self.width = width
    self.height = height
    self.depth = depth
    self.isSurface = isSurface
    self.intrinsics = intrinsics
    self.cameraToWorld = cameraToWorld
    self.timestamp = timestamp
  }
}

public actor Reconstructor {
  private var map = VoxelMap(voxelSize: 0.1)

  public init() {}

  public var voxelCount: Int { map.voxels.count }

  public func integrate(_ frame: DepthFrame) {
    map.integrate(frame)
  }

  public func model() async -> SceneModel {
    await extract(map.surfaceVoxels(), voxelSize: map.voxelSize)
  }
}

struct SurfaceVoxel: Sendable {
  var key: SIMD3<Int32>
  var position: SIMD3<Float>
  var isSoft: Bool
}

struct VoxelMap {
  let voxelSize: Float
  var voxels: [SIMD3<Int32>: Voxel] = [:]
  private var frameIndex: Int32 = 0

  init(voxelSize: Float) {
    self.voxelSize = voxelSize
  }

  mutating func integrate(_ frame: DepthFrame) {
    frameIndex += 1
    let second = Int32(frame.timestamp.rounded(.down))
    let origin = SIMD3<Float>(
      frame.cameraToWorld.columns.3.x, frame.cameraToWorld.columns.3.y,
      frame.cameraToWorld.columns.3.z)
    let fx = frame.intrinsics[0][0]
    let fy = frame.intrinsics[1][1]
    let cx = frame.intrinsics[2][0]
    let cy = frame.intrinsics[2][1]
    var points: [(position: SIMD3<Float>, isSurface: Bool)] = []
    for v in stride(from: 0, to: frame.height, by: pixelStride) {
      for u in stride(from: 0, to: frame.width, by: pixelStride) {
        let i = v * frame.width + u
        let d = frame.depth[i]
        guard d > minDepth, d < maxDepth else { continue }
        let camera = SIMD4<Float>((Float(u) - cx) * d / fx, -(Float(v) - cy) * d / fy, -d, 1)
        let world = frame.cameraToWorld * camera
        points.append((SIMD3(world.x, world.y, world.z), frame.isSurface[i]))
      }
    }
    for point in points where point.isSurface {
      voxels[key(point.position), default: Voxel()].addHit(
        point.position, frame: frameIndex, second: second)
    }
    for point in points {
      carve(from: origin, to: point.position, second: second)
    }
  }

  func surfaceVoxels() -> [SurfaceVoxel] {
    voxels.compactMap { key, voxel in
      guard voxel.hitFrames >= minHitFrames, voxel.hitSeconds * 2 >= voxel.seenSeconds else {
        return nil
      }
      let occupancy = Float(voxel.hitFrames) / Float(voxel.hitFrames + voxel.missFrames)
      return SurfaceVoxel(key: key, position: voxel.centroid, isSoft: occupancy < softOccupancy)
    }
  }

  private func key(_ point: SIMD3<Float>) -> SIMD3<Int32> {
    SIMD3<Int32>(point / voxelSize, rounding: .down)
  }

  private mutating func carve(from origin: SIMD3<Float>, to point: SIMD3<Float>, second: Int32) {
    let delta = point - origin
    let length = simd_length(delta)
    let end = length - carveMargin * voxelSize
    guard end > 0 else { return }
    let direction = delta / length
    var cell = key(origin)
    var step = SIMD3<Int32>.zero
    var tMax = SIMD3<Float>(repeating: .infinity)
    var tDelta = SIMD3<Float>(repeating: .infinity)
    for axis in 0..<3 where direction[axis] != 0 {
      let next = direction[axis] > 0 ? Float(cell[axis] + 1) : Float(cell[axis])
      step[axis] = direction[axis] > 0 ? 1 : -1
      tMax[axis] = (next * voxelSize - origin[axis]) / direction[axis]
      tDelta[axis] = voxelSize / abs(direction[axis])
    }
    var t: Float = 0
    while t < end {
      if let index = voxels.index(forKey: cell) {
        let offset = voxels.values[index].centroid - origin
        let along = simd_dot(offset, direction)
        if along < end, simd_length(offset - direction * along) < missRadius * voxelSize {
          voxels.values[index].addMiss(frame: frameIndex, second: second)
        }
      }
      let axis = tMax.x < tMax.y ? (tMax.x < tMax.z ? 0 : 2) : (tMax.y < tMax.z ? 1 : 2)
      t = tMax[axis]
      cell[axis] += step[axis]
      tMax[axis] += tDelta[axis]
    }
  }
}

struct Voxel {
  var sum = SIMD3<Float>.zero
  var samples: Int32 = 0
  var hitFrames: Int32 = 0
  var missFrames: Int32 = 0
  var hitSeconds: Int32 = 0
  var seenSeconds: Int32 = 0
  private var lastHitFrame: Int32 = -1
  private var lastMissFrame: Int32 = -1
  private var lastHitSecond: Int32 = .min
  private var lastSeenSecond: Int32 = .min

  var centroid: SIMD3<Float> { sum / Float(samples) }

  mutating func addHit(_ point: SIMD3<Float>, frame: Int32, second: Int32) {
    sum += point
    samples += 1
    if lastHitFrame != frame {
      lastHitFrame = frame
      hitFrames += 1
    }
    if lastHitSecond != second {
      lastHitSecond = second
      hitSeconds += 1
    }
    see(second)
  }

  mutating func addMiss(frame: Int32, second: Int32) {
    guard lastHitFrame != frame, lastMissFrame != frame else { return }
    lastMissFrame = frame
    missFrames += 1
    see(second)
  }

  private mutating func see(_ second: Int32) {
    guard lastSeenSecond != second else { return }
    lastSeenSecond = second
    seenSeconds += 1
  }
}

@concurrent private func extract(_ voxels: [SurfaceVoxel], voxelSize: Float) async -> SceneModel {
  var extraction = Extraction(voxels: voxels, voxelSize: voxelSize)
  return extraction.run()
}

private let pixelStride = 3
private let minDepth: Float = 0.3
private let maxDepth: Float = 5
private let carveMargin: Float = 1.5
private let missRadius: Float = 0.3
private let minHitFrames: Int32 = 3
private let softOccupancy: Float = 0.85
