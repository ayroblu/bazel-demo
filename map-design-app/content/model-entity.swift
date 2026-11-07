import RealityKit
import SwiftUI
import model

func modelEntity(_ model: SceneModel, opacity: Float) -> Entity {
  let root = Entity()
  for element in model.elements {
    guard let (mesh, transform) = geometry(element.shape) else { continue }
    let entity = ModelEntity(mesh: mesh, materials: [material(element.kind, opacity: opacity)])
    entity.transform = transform
    root.addChild(entity)
  }
  return root
}

private func geometry(_ shape: Solid) -> (MeshResource, Transform)? {
  switch shape {
  case .box(let transform, let size):
    return (.generateBox(size: size), Transform(matrix: transform))
  case .slab(let outline, let bottom, let top):
    let path = Path { path in
      path.addLines(outline.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
      path.closeSubpath()
    }
    var options = MeshResource.ShapeExtrusionOptions()
    options.extrusionMethod = .linear(depth: top - bottom)
    guard let mesh = try? MeshResource(extruding: path, extrusionOptions: options) else {
      return nil
    }
    return (
      mesh,
      Transform(
        rotation: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)),
        translation: SIMD3(0, (top + bottom) / 2, 0))
    )
  case .cylinder(let base, let radius, let height):
    return (
      .generateCylinder(height: height, radius: radius),
      Transform(translation: base + SIMD3(0, height / 2, 0))
    )
  case .ellipsoid(let transform, let radii):
    var placed = Transform(matrix: transform)
    placed.scale = radii
    return (.generateSphere(radius: 1), placed)
  }
}

private func material(_ kind: Kind, opacity: Float) -> SimpleMaterial {
  let color: UIColor =
    switch kind {
    case .floor: UIColor(white: 0.75, alpha: 1)
    case .surface: UIColor(white: 0.85, alpha: 1)
    case .wall: UIColor(white: 0.95, alpha: 1)
    case .door: .brown
    case .window: .systemTeal
    case .opening: .systemYellow
    case .object: .systemOrange
    case .pole: .systemGray
    case .trunk: UIColor(red: 0.45, green: 0.3, blue: 0.2, alpha: 1)
    case .canopy: .systemGreen
    }
  return SimpleMaterial(
    color: color.withAlphaComponent(CGFloat(opacity)), roughness: 0.8, isMetallic: false)
}
