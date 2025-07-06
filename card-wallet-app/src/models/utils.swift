class LazyValue<T> {
  private let getValue: () -> T
  init(_ getValue: @escaping () -> T) {
    self.getValue = getValue
  }
  lazy var value: T = getValue()
}
