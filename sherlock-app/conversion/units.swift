import Foundation

public struct Conversion: Sendable {
  public let result: String
  public let value: String
  public let detail: String
}

public func convertUnits(_ text: String) -> Conversion? {
  let pattern = /\s*(-?\d[\d,]*\.?\d*)\s*(\D.*?)\s+(?:in|to|as|into)\s+(.+?)\s*/
  guard let match = text.lowercased().wholeMatch(of: pattern),
    let amount = Double(match.1.replacing(",", with: "")),
    let from = unit(named: match.2), let to = unit(named: match.3),
    type(of: from).baseUnit().symbol == type(of: to).baseUnit().symbol
  else { return nil }
  let converted = Measurement(value: amount, unit: from).converted(to: to).value
  let result = "\(formatNumber(converted, grouping: true)) \(to.symbol)"
  return Conversion(
    result: result, value: formatNumber(converted, grouping: false),
    detail: "\(formatNumber(amount, grouping: true)) \(from.symbol) = \(result)")
}

func formatNumber(_ value: Double, grouping: Bool) -> String {
  let precision: NumberFormatStyleConfiguration.Precision =
    abs(value) >= 1 || value == 0 ? .fractionLength(0...4) : .significantDigits(1...4)
  return value.formatted(.number.precision(precision).grouping(grouping ? .automatic : .never))
}

private func unit(named name: Substring) -> Dimension? {
  let key = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  return unitAliases.first { $0.names.contains(key) }?.unit
}

private let unitAliases: [(names: Set<String>, unit: Dimension)] = [
  (["mm", "millimeter", "millimeters", "millimetre", "millimetres"], UnitLength.millimeters),
  (["cm", "centimeter", "centimeters", "centimetre", "centimetres"], UnitLength.centimeters),
  (["m", "meter", "meters", "metre", "metres"], UnitLength.meters),
  (["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers),
  (["in", "inch", "inches", "\""], UnitLength.inches),
  (["ft", "foot", "feet", "'"], UnitLength.feet),
  (["yd", "yard", "yards"], UnitLength.yards),
  (["mi", "mile", "miles"], UnitLength.miles),
  (["nmi", "nautical mile", "nautical miles"], UnitLength.nauticalMiles),
  (["mg", "milligram", "milligrams"], UnitMass.milligrams),
  (["g", "gram", "grams"], UnitMass.grams),
  (["kg", "kgs", "kilo", "kilos", "kilogram", "kilograms"], UnitMass.kilograms),
  (["t", "tonne", "tonnes"], UnitMass.metricTons),
  (["oz", "ounce", "ounces"], UnitMass.ounces),
  (["lb", "lbs", "pound", "pounds"], UnitMass.pounds),
  (["st", "stone", "stones"], UnitMass.stones),
  (["ml", "milliliter", "milliliters", "millilitre", "millilitres"], UnitVolume.milliliters),
  (["cl", "centiliter", "centiliters", "centilitre", "centilitres"], UnitVolume.centiliters),
  (["l", "liter", "liters", "litre", "litres"], UnitVolume.liters),
  (["tsp", "teaspoon", "teaspoons"], UnitVolume.teaspoons),
  (["tbsp", "tablespoon", "tablespoons"], UnitVolume.tablespoons),
  (["fl oz", "floz", "fluid ounce", "fluid ounces"], UnitVolume.fluidOunces),
  (["cup", "cups"], UnitVolume.cups),
  (["pt", "pint", "pints"], UnitVolume.pints),
  (["uk pint", "uk pints", "imperial pint", "imperial pints"], UnitVolume.imperialPints),
  (["gal", "gallon", "gallons"], UnitVolume.gallons),
  (["uk gal", "uk gallon", "uk gallons", "imperial gallon", "imperial gallons"], UnitVolume.imperialGallons),
  (["c", "°c", "celsius"], UnitTemperature.celsius),
  (["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit),
  (["k", "kelvin"], UnitTemperature.kelvin),
  (["km/h", "kmh", "kph"], UnitSpeed.kilometersPerHour),
  (["mph"], UnitSpeed.milesPerHour),
  (["m/s"], UnitSpeed.metersPerSecond),
  (["kn", "kt", "knot", "knots"], UnitSpeed.knots),
  (["ms", "millisecond", "milliseconds"], UnitDuration.milliseconds),
  (["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds),
  (["min", "mins", "minute", "minutes"], UnitDuration.minutes),
  (["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours),
  (["d", "day", "days"], UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))),
  (["wk", "week", "weeks"], UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))),
  (["b", "byte", "bytes"], UnitInformationStorage.bytes),
  (["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes),
  (["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes),
  (["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes),
  (["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes),
  (["kib", "kibibyte", "kibibytes"], UnitInformationStorage.kibibytes),
  (["mib", "mebibyte", "mebibytes"], UnitInformationStorage.mebibytes),
  (["gib", "gibibyte", "gibibytes"], UnitInformationStorage.gibibytes),
  (["tib", "tebibyte", "tebibytes"], UnitInformationStorage.tebibytes),
  (["m2", "m²", "sqm", "square meter", "square meters", "square metre", "square metres"], UnitArea.squareMeters),
  (["km2", "km²", "sqkm", "square kilometer", "square kilometers"], UnitArea.squareKilometers),
  (["ft2", "ft²", "sqft", "square foot", "square feet"], UnitArea.squareFeet),
  (["mi2", "mi²", "sqmi", "square mile", "square miles"], UnitArea.squareMiles),
  (["ac", "acre", "acres"], UnitArea.acres),
  (["ha", "hectare", "hectares"], UnitArea.hectares),
  (["j", "joule", "joules"], UnitEnergy.joules),
  (["kj", "kilojoule", "kilojoules"], UnitEnergy.kilojoules),
  (["cal", "calorie", "calories"], UnitEnergy.calories),
  (["kcal", "kilocalorie", "kilocalories"], UnitEnergy.kilocalories),
  (["kwh", "kilowatt hour", "kilowatt hours"], UnitEnergy.kilowattHours),
  (["deg", "°", "degree", "degrees"], UnitAngle.degrees),
  (["rad", "radian", "radians"], UnitAngle.radians),
]
