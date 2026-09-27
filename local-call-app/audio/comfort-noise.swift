import Foundation

public nonisolated enum ComfortNoise {
  public static let amplitude: Float = 0.012

  public static func frame(samples: Int) -> [Float] {
    (0..<samples).map { _ in Float.random(in: -amplitude...amplitude) }
  }
}
