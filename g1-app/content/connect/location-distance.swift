import MapKit

func calculateRouteProgress(route: MKRoute, currentLocation: CLLocation) -> (
  remainingDistance: Double, remainingDuration: TimeInterval, currentStep: MKRoute.Step?,
  remainingStepDistance: Double?
) {
  let polyline = route.polyline

  let (coordinate, remainingDistance) = findNearestCoordinate(
    polyline: polyline, currentLocation: currentLocation)

  // Find current step
  let currentStep: MKRoute.Step? = route.steps.last(where: { step in
    let stepPolyline = step.polyline
    var stepCoordinates = [CLLocationCoordinate2D](
      repeating: kCLLocationCoordinate2DInvalid, count: stepPolyline.pointCount)
    stepPolyline.getCoordinates(
      &stepCoordinates, range: NSRange(location: 0, length: stepPolyline.pointCount))
    for coord in stepCoordinates {
      if coord.latitude == coordinate.latitude
        && coord.longitude == coordinate.longitude
      {
        return true
      }
    }
    return false
  })
  let remainingStepDistance = currentStep.map { step in
    let stepPolyline = step.polyline
    let (_, remainingDistance) = findNearestCoordinate(
      polyline: stepPolyline, currentLocation: currentLocation)
    return remainingDistance
  }

  // Calculate remaining duration based on proportion of distance remaining
  let remainingProgress = remainingDistance / route.distance
  let remainingDuration = route.expectedTravelTime * remainingProgress

  return (
    remainingDistance: remainingDistance, remainingDuration: remainingDuration,
    currentStep: currentStep, remainingStepDistance: remainingStepDistance
  )
}

func findNearestCoordinate(polyline: MKPolyline, currentLocation: CLLocation) -> (
  coordinate: CLLocationCoordinate2D, remainingDistance: Double
) {

  let pointCount = polyline.pointCount
  var coordinates = [CLLocationCoordinate2D](
    repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
  polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))

  var closestDistance = Double.greatestFiniteMagnitude
  var closestCoordinateIndex = 0
  var nearestCoordinate: CLLocationCoordinate2D = coordinates.first!

  for (index, coordinate) in coordinates.enumerated() {
    let routePoint = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let distance = currentLocation.distance(from: routePoint)
    if distance < closestDistance {
      closestDistance = distance
      closestCoordinateIndex = index
      nearestCoordinate = coordinate
    }
  }

  var remainingDistance: Double =
    coordinates.count > closestCoordinateIndex + 1
    ? projectedDistanceRemaining(
      startLocation: coordinates[closestCoordinateIndex],
      endLocation: coordinates[closestCoordinateIndex + 1],
      current: currentLocation)
    : 0
  for i in (closestCoordinateIndex + 2)..<coordinates.count {
    let point1 = CLLocation(
      latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
    let point2 = CLLocation(
      latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
    remainingDistance += point1.distance(from: point2)
  }

  return (coordinate: nearestCoordinate, remainingDistance: remainingDistance)
}

func projectedDistanceRemaining(
  startLocation: CLLocationCoordinate2D, endLocation: CLLocationCoordinate2D, current: CLLocation
) -> Double {
  let a = endLocation.distance(from: current)
  let b = startLocation.distance(from: current)
  let c = startLocation.distance(from: endLocation)

  // Use law of cosines
  let denominator = (2 * a * c)
  guard denominator > 0 else { return 0.0 }
  let cosTheta = (pow(a, 2) + pow(c, 2) - pow(b, 2)) / denominator

  return a * cosTheta
}
extension CLLocationCoordinate2D {
  func distance(from: CLLocationCoordinate2D) -> Double {
    let loc = CLLocation(latitude: self.latitude, longitude: self.longitude)
    let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
    return loc.distance(from: fromLoc)
  }

  func distance(from: CLLocation) -> Double {
    let loc = CLLocation(latitude: self.latitude, longitude: self.longitude)
    return loc.distance(from: from)
  }
}
