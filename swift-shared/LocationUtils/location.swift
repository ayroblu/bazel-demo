import Foundation

public func calculateDistance(_ loc1: (Double, Double), _ loc2: (Double, Double)) -> Double {
  let (lat1, lon1) = loc1
  let (lat2, lon2) = loc2
  // Earth's radius in kilometers
  let earthRadius = 6371.0

  // Convert latitude and longitude from degrees to radians
  let lat1Rad = lat1 * .pi / 180
  let lon1Rad = lon1 * .pi / 180
  let lat2Rad = lat2 * .pi / 180
  let lon2Rad = lon2 * .pi / 180

  // Differences in coordinates
  let deltaLat = lat2Rad - lat1Rad
  let deltaLon = lon2Rad - lon1Rad

  // Haversine formula
  let a =
    sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1Rad) * cos(lat2Rad) * sin(deltaLon / 2)
    * sin(deltaLon / 2)
  let c = 2 * atan2(sqrt(a), sqrt(1 - a))

  // Distance in kilometers
  let distance = earthRadius * c

  return distance
}
