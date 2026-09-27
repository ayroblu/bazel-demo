import Foundation

/// Quiet white noise for stretches where no audio arrives: dead air reads as
/// a dropped call, a faint hiss reads as a live line with nothing on it.
public nonisolated enum ComfortNoise {
  public static let amplitude: Float = 0.012

  public static func frame(samples: Int) -> [Float] {
    (0..<samples).map { _ in Float.random(in: -amplitude...amplitude) }
  }
}
