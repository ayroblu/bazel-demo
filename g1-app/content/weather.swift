import CoreLocation
import Foundation
import Log

let USER_LAT = "user-lat"
let USER_LNG = "user-lng"

extension ConnectionManager {
  func checkWeather() {
    guard isStale() else { return }
    Task {
      let loc = getCurrentLocation()
      if let loc {
        UserDefaults.standard.set(loc.coordinate.latitude, forKey: USER_LAT)
        UserDefaults.standard.set(loc.coordinate.longitude, forKey: USER_LNG)
      } else {
        log("failed to pull location")
      }
      guard let lat = loc?.coordinate.latitude ?? udDouble(forKey: USER_LAT)
      else { return }
      guard let lng = loc?.coordinate.longitude ?? udDouble(forKey: USER_LNG)
      else { return }
      let latStr = String(format: "%.2f", lat)
      let lngStr = String(format: "%.2f", lng)
      guard let weather = await fetchWeather(lat: latStr, lng: lngStr) else {
        log("failed to fetch weather")
        return
      }
      log("fetched weather", weather)
      let weatherData = G1Cmd.Config.dashTimeWeatherData(
        weatherIcon: parseWeatherIcon(
          code: weather.current.weather_code, isDay: weather.current.is_day == 1),
        temp: UInt8(round(weather.current.temperature_2m)))
      manager.transmitBoth(weatherData)
      lastFetch = Date()
    }
  }
}
var lastFetch: Date? = nil
func isStale() -> Bool {
  guard let lastFetch else { return true }
  return Date().timeIntervalSince(lastFetch) > 3600
}

func udDouble(forKey: String) -> Double? {
  if UserDefaults.standard.object(forKey: forKey) != nil {
    return UserDefaults.standard.double(forKey: forKey)
  } else {
    return nil
  }
}

struct CurrentWeather: Codable {
  let time: String
  let interval: Int
  let temperature_2m: Double
  let weather_code: Int
  let is_day: Int
}
struct WeatherResult: Codable {
  let current: CurrentWeather

  // enum CodingKeys: String, CodingKey {
  //   case email
  // }
}
func fetchWeather(lat: String, lng: String) async -> WeatherResult? {
  guard
    let url = URL(
      string:
        "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)&current=temperature_2m,weather_code,is_day"
    )
  else {
    return nil
  }

  guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
  let decoder = JSONDecoder()
  return try? decoder.decode(WeatherResult.self, from: data)
}

func getCurrentLocation() -> CLLocation? {
  let locManager = CLLocationManager()
  switch locManager.authorizationStatus {
  case .authorizedWhenInUse, .authorizedAlways:
    return locManager.location
  default:
    return nil
  }
}

func parseWeatherIcon(code: Int, isDay: Bool) -> G1Cmd.Config.WeatherIcon {
  // See: `WMO Weather interpretation codes (WW)` of https://open-meteo.com/en/docs
  switch code {
  case 0, 1:
    return isDay ? G1Cmd.Config.WeatherIcon.Sunny : G1Cmd.Config.WeatherIcon.Night
  case 2, 3:
    return G1Cmd.Config.WeatherIcon.Clouds
  case 45, 48:
    return G1Cmd.Config.WeatherIcon.Fog
  case 51, 53, 56:
    return G1Cmd.Config.WeatherIcon.Drizzle
  case 55, 57:
    return G1Cmd.Config.WeatherIcon.HeavyDrizzle
  case 61, 63, 66, 80, 81, 82:
    return G1Cmd.Config.WeatherIcon.Rain
  case 65, 67:
    return G1Cmd.Config.WeatherIcon.HeavyRain
  case 95, 96:
    return G1Cmd.Config.WeatherIcon.Thunder
  case 99:
    return G1Cmd.Config.WeatherIcon.ThunderStorm
  case 71, 73, 75, 77, 85, 86:
    return G1Cmd.Config.WeatherIcon.Snow
  default:
    log("Unknown weather code", code)
    return G1Cmd.Config.WeatherIcon.Tornado
  // case 0:
  //   return G1Cmd.Config.WeatherIcon.Mist
  // case 0:
  //   return G1Cmd.Config.WeatherIcon.Sand
  // case 0:
  //   return G1Cmd.Config.WeatherIcon.Squalls
  // case 0:
  //   return G1Cmd.Config.WeatherIcon.Tornado
  // case 0:
  //   return G1Cmd.Config.WeatherIcon.Freezing
  }
}
