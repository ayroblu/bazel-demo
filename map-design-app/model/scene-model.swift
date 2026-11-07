import simd

public struct SceneModel: Sendable {
  public var elements: [Element]

  public init(elements: [Element] = []) {
    self.elements = elements
  }
}

public struct Element: Sendable {
  public var kind: Kind
  public var shape: Solid

  public init(kind: Kind, shape: Solid) {
    self.kind = kind
    self.shape = shape
  }
}

public enum Kind: Sendable {
  case floor
  case surface
  case wall
  case door
  case window
  case opening
  case object
  case pole
  case trunk
  case canopy
}

public enum Solid: Sendable {
  case box(transform: simd_float4x4, size: SIMD3<Float>)
  case slab(outline: [SIMD2<Float>], bottom: Float, top: Float)
  case cylinder(base: SIMD3<Float>, radius: Float, height: Float)
  case ellipsoid(transform: simd_float4x4, radii: SIMD3<Float>)
}

public func yawTransform(center: SIMD3<Float>, xAxis: SIMD3<Float>) -> simd_float4x4 {
  let up = SIMD3<Float>(0, 1, 0)
  let zAxis = simd_cross(xAxis, up)
  return simd_float4x4(
    SIMD4(xAxis, 0), SIMD4(up, 0), SIMD4(zAxis, 0), SIMD4(center, 1))
}
