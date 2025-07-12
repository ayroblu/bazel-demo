public class LazyValue<T> {
  private let getValue: () -> T
  init(_ getValue: @escaping () -> T) {
    self.getValue = getValue
  }
  public lazy var value: T = getValue()
}
