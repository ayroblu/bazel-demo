import model
import simd

struct Extraction {
  private let voxels: [SurfaceVoxel]
  private let s: Float
  private let index: [SIMD3<Int32>: Int]
  private var normals: [SIMD3<Float>?]
  private var used: [Bool]
  private var slabs: [Slab] = []
  private var manhattan: Float?
  private var elements: [Element] = []

  init(voxels: [SurfaceVoxel], voxelSize: Float) {
    self.voxels = voxels
    s = voxelSize
    index = Dictionary(uniqueKeysWithValues: voxels.enumerated().map { ($1.key, $0) })
    normals = Array(repeating: nil, count: voxels.count)
    used = Array(repeating: false, count: voxels.count)
  }

  mutating func run() -> SceneModel {
    estimateNormals()
    extractSlabs()
    extractWalls()
    extractObjects()
    return SceneModel(elements: elements)
  }

  private mutating func estimateNormals() {
    let offsets = neighborOffsets(radius: 1)
    for i in voxels.indices where !voxels[i].isSoft {
      let points = offsets.compactMap { offset -> SIMD3<Float>? in
        guard let j = index[voxels[i].key &+ offset], !voxels[j].isSoft else { return nil }
        return voxels[j].position
      }
      guard points.count >= minNeighbors else { continue }
      let fit = planeFit(points)
      if fit.flatness < maxFlatness {
        normals[i] = fit.normal
      }
    }
  }

  private mutating func extractSlabs() {
    let candidates = voxels.indices.filter { normals[$0].map { abs($0.y) > horizontalNormal } ?? false }
    var found: [Slab] = []
    for plane in planes(candidates, offset: { voxels[$0].position.y }, minCount: minPlaneVoxels) {
      let cells = components2D(plane.members) { SIMD2(voxels[$0].key.x, voxels[$0].key.z) }
      for component in cells where component.count >= minSlabCells {
        let corners = component.flatMap { i -> [SIMD2<Float>] in
          let base = SIMD2(Float(voxels[i].key.x), Float(voxels[i].key.z))
          return [SIMD2<Float>(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)].map { (base + $0) * s }
        }
        let outline = convexHull(corners)
        found.append(
          Slab(outline: outline, height: plane.offset, area: polygonArea(outline), members: component))
      }
    }
    let maxArea = found.map(\.area).max() ?? 0
    let floorHeight = found.filter { $0.area >= maxArea / 2 }.map(\.height).min() ?? 0
    let s = s
    for slab in found {
      let isFloor = abs(slab.height - floorHeight) <= floorTolerance
      guard isFloor || slab.height - floorHeight >= ceilingClearance else { continue }
      slabs.append(slab)
      for i in slab.members { used[i] = true }
      absorb {
        abs($0.y - slab.height) <= s && polygonContains(slab.outline, SIMD2($0.x, $0.z))
      }
      elements.append(
        Element(
          kind: isFloor ? .floor : .surface,
          shape: .slab(outline: slab.outline, bottom: slab.height - slabThickness, top: slab.height)
        ))
    }
  }

  private mutating func extractWalls() {
    let candidates = voxels.indices.filter {
      !used[$0] && (normals[$0].map { abs($0.y) < verticalNormal } ?? false)
    }
    let angles = candidates.map { i in
      let normal = normals[i]!
      return foldedAngle(atan2(normal.z, normal.x))
    }
    var histogram = [Int](repeating: 0, count: angleBins)
    for angle in angles {
      histogram[min(Int(angle / angleBinWidth), angleBins - 1)] += 1
    }
    let smoothed = (0..<angleBins).map {
      histogram[($0 + angleBins - 1) % angleBins] + 2 * histogram[$0]
        + histogram[($0 + 1) % angleBins]
    }
    var directions: [Float] = []
    for bin in (0..<angleBins).sorted(by: { smoothed[$0] > smoothed[$1] }) {
      guard smoothed[bin] >= 4 * minWallVoxels else { break }
      let angle = (Float(bin) + 0.5) * angleBinWidth
      if directions.allSatisfy({ angularDistance($0, angle) > directionSeparation }) {
        directions.append(angle)
      }
    }
    guard let dominant = directions.first else { return }
    manhattan = dominant
    for direction in directions.map({ snapDirection($0, to: dominant) }) {
      let normal = SIMD3<Float>(cos(direction), 0, sin(direction))
      let tangent = SIMD3<Float>(-sin(direction), 0, cos(direction))
      let members = zip(candidates, angles).filter {
        !used[$0.0] && angularDistance($0.1, direction) <= wallMemberAngle
      }.map(\.0)
      for plane in planes(
        members, offset: { simd_dot(normal, voxels[$0].position) }, minCount: minWallVoxels)
      {
        let cells = components2D(plane.members) {
          SIMD2(Int32((simd_dot(tangent, voxels[$0].position) / s).rounded(.down)), voxels[$0].key.y)
        }
        for component in cells where component.count >= minWallVoxels {
          let ts = component.map { simd_dot(tangent, voxels[$0].position) }
          let ys = component.map { voxels[$0].position.y }
          let t0 = ts.min()! - s / 2
          let t1 = ts.max()! + s / 2
          let y0 = ys.min()! - s / 2
          let y1 = ys.max()! + s / 2
          guard t1 - t0 >= minWallLength, y1 - y0 >= minWallHeight else { continue }
          for i in component { used[i] = true }
          let s = s
          absorb {
            let t = simd_dot(tangent, $0)
            return abs(simd_dot(normal, $0) - plane.offset) <= s && t >= t0 && t <= t1
              && $0.y >= y0 && $0.y <= y1
          }
          let center = normal * plane.offset + tangent * (t0 + t1) / 2 + SIMD3(0, (y0 + y1) / 2, 0)
          elements.append(
            Element(
              kind: .wall,
              shape: .box(
                transform: yawTransform(center: center, xAxis: tangent),
                size: SIMD3(t1 - t0, y1 - y0, wallThickness))))
        }
      }
    }
  }

  private mutating func extractObjects() {
    let soft = voxels.indices.filter { !used[$0] && voxels[$0].isSoft }
    var canopies: [OrientedBox] = []
    var leftovers: [Int] = []
    for component in components3D(soft, radius: 2) {
      guard component.count >= minCanopyVoxels else {
        leftovers += component
        continue
      }
      let box = orientedBox(component)
      canopies.append(box)
      absorb { box.contains($0) }
      elements.append(
        Element(kind: .canopy, shape: .ellipsoid(transform: box.transform, radii: box.size / 2)))
    }
    let solid = voxels.indices.filter { !used[$0] && !voxels[$0].isSoft } + leftovers
    for component in components3D(solid, radius: 1) where component.count >= minObjectVoxels {
      let box = groundedBox(orientedBox(component))
      guard box.size.x <= maxPoleWidth, box.size.z <= maxPoleWidth, box.size.y >= minPoleHeight
      else {
        elements.append(Element(kind: .object, shape: .box(transform: box.transform, size: box.size)))
        continue
      }
      let isTrunk = canopies.contains {
        simd_distance(SIMD2($0.center.x, $0.center.z), SIMD2(box.center.x, box.center.z))
          <= max($0.size.x, $0.size.z) / 2 && $0.bottom <= box.top + trunkCanopyGap
      }
      elements.append(
        Element(
          kind: isTrunk ? .trunk : .pole,
          shape: .cylinder(
            base: SIMD3(box.center.x, box.bottom, box.center.z),
            radius: (box.size.x + box.size.z) / 4, height: box.size.y)))
    }
  }

  private func planes(_ members: [Int], offset: (Int) -> Float, minCount: Int) -> [Plane] {
    var bins: [Int32: [Int]] = [:]
    for i in members {
      bins[Int32((offset(i) / s).rounded(.down)), default: []].append(i)
    }
    var taken = Set<Int32>()
    var planes: [Plane] = []
    for (bin, binMembers) in bins.sorted(by: { $0.value.count > $1.value.count }) {
      guard binMembers.count >= minCount, !taken.contains(bin) else { continue }
      let near = (bin - 1...bin + 1).filter { !taken.contains($0) }
      taken.formUnion(near)
      let planeMembers = near.flatMap { bins[$0] ?? [] }
      let mean = planeMembers.map(offset).reduce(0, +) / Float(planeMembers.count)
      planes.append(Plane(members: planeMembers, offset: mean))
    }
    return planes
  }

  private func components2D(_ members: [Int], cell: (Int) -> SIMD2<Int32>) -> [[Int]] {
    var cells: [SIMD2<Int32>: [Int]] = [:]
    for i in members {
      cells[cell(i), default: []].append(i)
    }
    var components: [[Int]] = []
    for i in members {
      let start = cell(i)
      guard var component = cells.removeValue(forKey: start) else { continue }
      var queue = [start]
      var head = 0
      while head < queue.count {
        let current = queue[head]
        head += 1
        for dx in Int32(-2)...2 {
          for dy in Int32(-2)...2 {
            let next = current &+ SIMD2(dx, dy)
            if let more = cells.removeValue(forKey: next) {
              component += more
              queue.append(next)
            }
          }
        }
      }
      components.append(component)
    }
    return components
  }

  private mutating func absorb(_ isInside: (SIMD3<Float>) -> Bool) {
    for i in voxels.indices where !used[i] && !voxels[i].isSoft && isInside(voxels[i].position) {
      used[i] = true
    }
  }

  private func components3D(_ members: [Int], radius: Int32) -> [[Int]] {
    var isMember = [Bool](repeating: false, count: voxels.count)
    for i in members {
      isMember[i] = true
    }
    let offsets = neighborOffsets(radius: radius)
    var components: [[Int]] = []
    for start in members where isMember[start] {
      isMember[start] = false
      var component = [start]
      var head = 0
      while head < component.count {
        let key = voxels[component[head]].key
        head += 1
        for offset in offsets {
          if let j = index[key &+ offset], isMember[j] {
            isMember[j] = false
            component.append(j)
          }
        }
      }
      components.append(component)
    }
    return components
  }

  private func orientedBox(_ component: [Int]) -> OrientedBox {
    let points = component.map { voxels[$0].position }
    let yaw = snapYaw(principalYaw(points))
    let xAxis = SIMD3<Float>(cos(yaw), 0, sin(yaw))
    let zAxis = simd_cross(xAxis, SIMD3(0, 1, 0))
    let local = points.map { SIMD3(simd_dot($0, xAxis), $0.y, simd_dot($0, zAxis)) }
    let low = local.reduce(SIMD3(repeating: .infinity)) { simd_min($0, $1) }
    let high = local.reduce(SIMD3(repeating: -.infinity)) { simd_max($0, $1) }
    let mid = (low + high) / 2
    return OrientedBox(
      center: xAxis * mid.x + SIMD3(0, mid.y, 0) + zAxis * mid.z,
      size: high - low + s, xAxis: xAxis)
  }

  private func snapYaw(_ yaw: Float) -> Float {
    guard let manhattan else { return yaw }
    let quarter = Float.pi / 2
    let d = (yaw - manhattan).truncatingRemainder(dividingBy: quarter)
    let remainder = d < 0 ? d + quarter : d
    if remainder <= yawSnap { return yaw - remainder }
    if quarter - remainder <= yawSnap { return yaw + quarter - remainder }
    return yaw
  }

  private func groundedBox(_ box: OrientedBox) -> OrientedBox {
    let xz = SIMD2(box.center.x, box.center.z)
    guard
      let ground = slabs.filter({
        $0.height <= box.bottom + s && box.bottom - $0.height <= maxGroundGap
          && polygonContains($0.outline, xz)
      }).map(\.height).max()
    else { return box }
    var grounded = box
    grounded.size.y = box.top - ground
    grounded.center.y = (box.top + ground) / 2
    return grounded
  }
}

private struct Slab {
  var outline: [SIMD2<Float>]
  var height: Float
  var area: Float
  var members: [Int]
}

private struct Plane {
  var members: [Int]
  var offset: Float
}

private struct OrientedBox {
  var center: SIMD3<Float>
  var size: SIMD3<Float>
  var xAxis: SIMD3<Float>

  var bottom: Float { center.y - size.y / 2 }
  var top: Float { center.y + size.y / 2 }
  var transform: simd_float4x4 { yawTransform(center: center, xAxis: xAxis) }

  func contains(_ point: SIMD3<Float>) -> Bool {
    let d = point - center
    let zAxis = simd_cross(xAxis, SIMD3(0, 1, 0))
    return abs(simd_dot(d, xAxis)) <= size.x / 2 && abs(d.y) <= size.y / 2
      && abs(simd_dot(d, zAxis)) <= size.z / 2
  }
}

private func neighborOffsets(radius: Int32) -> [SIMD3<Int32>] {
  (-radius...radius).flatMap { x in
    (-radius...radius).flatMap { y in (-radius...radius).map { z in SIMD3(x, y, z) } }
  }
}

private func planeFit(_ points: [SIMD3<Float>]) -> (normal: SIMD3<Float>, flatness: Float) {
  let mean = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
  var covariance = [Double](repeating: 0, count: 9)
  for point in points {
    let d = SIMD3<Double>(point - mean)
    for r in 0..<3 {
      for c in 0..<3 {
        covariance[r * 3 + c] += d[r] * d[c]
      }
    }
  }
  let (values, vectors) = symmetricEigen(covariance)
  let smallest = (0..<3).min { values[$0] < values[$1] }!
  let total = values.reduce(0, +)
  let normal = SIMD3<Float>(
    Float(vectors[smallest]), Float(vectors[3 + smallest]), Float(vectors[6 + smallest]))
  return (simd_normalize(normal), total > 0 ? Float(values[smallest] / total) : 1)
}

private func symmetricEigen(_ matrix: [Double]) -> (values: [Double], vectors: [Double]) {
  var a = matrix
  var v: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
  for _ in 0..<32 {
    guard a[1] * a[1] + a[2] * a[2] + a[5] * a[5] > 1e-20 else { break }
    for (p, q) in [(0, 1), (0, 2), (1, 2)] where abs(a[p * 3 + q]) > 1e-30 {
      let theta = (a[q * 3 + q] - a[p * 3 + p]) / (2 * a[p * 3 + q])
      let t = (theta >= 0 ? 1 : -1) / (abs(theta) + (theta * theta + 1).squareRoot())
      let c = 1 / (t * t + 1).squareRoot()
      let s = t * c
      for k in 0..<3 {
        let kp = a[k * 3 + p]
        let kq = a[k * 3 + q]
        a[k * 3 + p] = c * kp - s * kq
        a[k * 3 + q] = s * kp + c * kq
      }
      for k in 0..<3 {
        let pk = a[p * 3 + k]
        let qk = a[q * 3 + k]
        a[p * 3 + k] = c * pk - s * qk
        a[q * 3 + k] = s * pk + c * qk
      }
      for k in 0..<3 {
        let kp = v[k * 3 + p]
        let kq = v[k * 3 + q]
        v[k * 3 + p] = c * kp - s * kq
        v[k * 3 + q] = s * kp + c * kq
      }
    }
  }
  return ([a[0], a[4], a[8]], v)
}

private func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
  let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
  guard sorted.count > 2 else { return sorted }
  var lower: [SIMD2<Float>] = []
  for point in sorted {
    while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
      lower.removeLast()
    }
    lower.append(point)
  }
  var upper: [SIMD2<Float>] = []
  for point in sorted.reversed() {
    while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
      upper.removeLast()
    }
    upper.append(point)
  }
  return lower.dropLast() + upper.dropLast()
}

private func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
  (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
}

private func polygonArea(_ outline: [SIMD2<Float>]) -> Float {
  abs(
    outline.indices.reduce(0) { area, i in
      let a = outline[i]
      let b = outline[(i + 1) % outline.count]
      return area + a.x * b.y - b.x * a.y
    } / 2)
}

private func polygonContains(_ outline: [SIMD2<Float>], _ point: SIMD2<Float>) -> Bool {
  outline.indices.allSatisfy { cross(outline[$0], outline[($0 + 1) % outline.count], point) >= 0 }
}

private func foldedAngle(_ angle: Float) -> Float {
  let folded = angle.truncatingRemainder(dividingBy: .pi)
  return folded < 0 ? folded + .pi : folded
}

private func angularDistance(_ a: Float, _ b: Float) -> Float {
  let d = foldedAngle(a - b)
  return min(d, .pi - d)
}

private func snapDirection(_ angle: Float, to dominant: Float) -> Float {
  for candidate in [dominant, foldedAngle(dominant + .pi / 2)]
  where angularDistance(angle, candidate) <= directionSnap {
    return candidate
  }
  return angle
}

private func principalYaw(_ points: [SIMD3<Float>]) -> Float {
  let mean = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
  var xx: Float = 0
  var xz: Float = 0
  var zz: Float = 0
  for point in points {
    let d = point - mean
    xx += d.x * d.x
    xz += d.x * d.z
    zz += d.z * d.z
  }
  return atan2(2 * xz, xx - zz) / 2
}

private let minNeighbors = 6
private let maxFlatness: Float = 0.06
private let horizontalNormal: Float = 0.9
private let verticalNormal: Float = 0.3
private let minPlaneVoxels = 30
private let minSlabCells = 25
private let slabThickness: Float = 0.05
private let floorTolerance: Float = 0.15
private let ceilingClearance: Float = 1.8
private let angleBins = 90
private let angleBinWidth = Float.pi / Float(angleBins)
private let directionSeparation = Float.pi / 18
private let directionSnap = Float.pi / 30
private let wallMemberAngle = Float.pi / 15
private let minWallVoxels = 25
private let minWallLength: Float = 0.5
private let minWallHeight: Float = 1
private let wallThickness: Float = 0.1
private let minCanopyVoxels = 25
private let minObjectVoxels = 10
private let maxPoleWidth: Float = 0.5
private let minPoleHeight: Float = 1
private let trunkCanopyGap: Float = 0.5
private let maxGroundGap: Float = 0.3
private let yawSnap = Float.pi / 12
