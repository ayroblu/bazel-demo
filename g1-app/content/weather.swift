import CoreLocation
import Foundation
import Log
import g1protocol

extension ConnectionManager {
  func checkWeather() {
    guard isStale() else { return }
    Task {
      if let weather = await getWeather() {
        let weatherData = Config.dashTimeWeatherData(
          weatherIcon: parseWeatherIcon(
            code: weather.current.weather_code, isDay: weather.current.is_day == 1),
          temp: UInt8(round(weather.current.temperature_2m)))
        bluetoothManager.transmitBoth(weatherData)
        lastFetch = Date()
      } else {
        let weatherData = Config.dashTimeWeatherData(
          weatherIcon: Config.WeatherIcon.Sunny,
          temp: UInt8(25))
        bluetoothManager.transmitBoth(weatherData)
        lastFetch = Date()
      }
    }
  }
}
var lastFetch: Date? = nil
func isStale() -> Bool {
  guard let lastFetch else { return true }
  return Date().timeIntervalSince(lastFetch) > 3600
}

func getWeather() async -> WeatherResult? {
  let loc = getCurrentLocation()
  if let loc {
    userLatState.set(loc.coordinate.latitude)
    userLngState.set(loc.coordinate.longitude)
  } else {
    log("failed to pull location")
  }
  guard let lat = loc?.coordinate.latitude ?? userLatState.get()
  else { return nil }
  guard let lng = loc?.coordinate.longitude ?? userLngState.get()
  else { return nil }
  let latStr = String(format: "%.2f", lat)
  let lngStr = String(format: "%.2f", lng)
  guard let weather = await fetchWeather(lat: latStr, lng: lngStr) else {
    log("failed to fetch weather")
    return nil
  }
  log("fetched weather", weather)
  return weather
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

func parseWeatherIcon(code: Int, isDay: Bool) -> Config.WeatherIcon {
  // See: `WMO Weather interpretation codes (WW)` of https://open-meteo.com/en/docs
  switch code {
  case 0, 1:
    return isDay ? Config.WeatherIcon.Sunny : Config.WeatherIcon.Night
  case 2, 3:
    return Config.WeatherIcon.Clouds
  case 45, 48:
    return Config.WeatherIcon.Fog
  case 51, 53, 56:
    return Config.WeatherIcon.Drizzle
  case 55, 57:
    return Config.WeatherIcon.HeavyDrizzle
  case 61, 63, 66, 80, 81, 82:
    return Config.WeatherIcon.Rain
  case 65, 67:
    return Config.WeatherIcon.HeavyRain
  case 95, 96:
    return Config.WeatherIcon.Thunder
  case 99:
    return Config.WeatherIcon.ThunderStorm
  case 71, 73, 75, 77, 85, 86:
    return Config.WeatherIcon.Snow
  default:
    log("Unknown weather code", code)
    return Config.WeatherIcon.Tornado
  // case 0:
  //   return Config.WeatherIcon.Mist
  // case 0:
  //   return Config.WeatherIcon.Sand
  // case 0:
  //   return Config.WeatherIcon.Squalls
  // case 0:
  //   return Config.WeatherIcon.Tornado
  // case 0:
  //   return Config.WeatherIcon.Freezing
  }
}
