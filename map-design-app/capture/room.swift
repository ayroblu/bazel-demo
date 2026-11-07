import RoomPlan
import model
import simd

extension SceneModel {
  public init(room: CapturedRoom) {
    var elements: [Element] = []
    for floor in room.floors {
      let corners = floor.polygonCorners.map { floor.transform * SIMD4($0, 1) }
      let height = floor.transform.columns.3.y
      elements.append(
        Element(
          kind: .floor,
          shape: corners.count >= 3
            ? .slab(outline: corners.map { SIMD2($0.x, $0.z) }, bottom: height - 0.05, top: height)
            : .box(
              transform: floor.transform, size: SIMD3(floor.dimensions.x, floor.dimensions.y, 0.05))
        ))
    }
    let surfaces: [(Kind, [CapturedRoom.Surface], Float)] = [
      (.wall, room.walls, 0.1), (.door, room.doors, 0.14), (.window, room.windows, 0.14),
      (.opening, room.openings, 0.12),
    ]
    for (kind, items, thickness) in surfaces {
      for surface in items {
        elements.append(
          Element(
            kind: kind,
            shape: .box(
              transform: surface.transform,
              size: SIMD3(surface.dimensions.x, surface.dimensions.y, thickness))))
      }
    }
    for object in room.objects {
      elements.append(
        Element(kind: .object, shape: .box(transform: object.transform, size: object.dimensions)))
    }
    self.init(elements: elements)
  }
}
