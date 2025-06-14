import Combine
import SwiftUI

extension ObservableObjectPublisher: Subscriber {
  public func receiveUpdate() {
    send()
  }
}

@MainActor
public class AtomValue<T>: ObservableObject where T: Equatable {
  public let objectWillChange = ObservableObjectPublisher()

  public let store: Store
  public let atom: Atom<T>

  private let disposer: Disposable

  public var value: T {
    get {
      return store.get(atom)
    }
    set {
      store.set(atom, value: newValue)
    }
  }

  public var binding: Binding<T> {
    .init {
      self.value
    } set: {
      self.value = $0
    }
  }

  deinit {
    disposer.dispose()
  }

  public init(_ atom: Atom<T>) {
    self.store = Store.shared
    self.atom = atom

    self.disposer = store.subscribe(atom: atom, subscriber: objectWillChange)
  }
}
