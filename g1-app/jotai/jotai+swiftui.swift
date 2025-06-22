import Foundation
import SwiftUI

private class ValueModel<T: Equatable>: ObservableObject {
  @Published var value: T
  var dispose: (() -> Void)?
  init(value: T) {
    self.value = value
  }
  func listen(store: JotaiStore, atom: Atom<T>) {
    dispose = store.sub(atom: atom) { [weak self, weak atom, weak store] in
      guard let self, let atom, let store else { return }
      self.value = store.get(atom: atom)
    }
  }
  deinit {
    // TODO: write a test to validate this
    dispose?()
  }
}

@propertyWrapper
public struct AtomState<T: Equatable>: DynamicProperty {
  @StateObject private var model: ValueModel<T>
  private let store: JotaiStore
  private let atom: WritableAtom<T, T, Void>

  public init(_ atom: WritableAtom<T, T, Void>, store maybeStore: JotaiStore? = nil) {
    self.atom = atom
    self.store = maybeStore ?? JotaiStore.shared
    let valueModel = ValueModel(value: store.get(atom: atom))
    valueModel.listen(store: store, atom: atom)
    self._model = StateObject(wrappedValue: valueModel)
  }

  public var wrappedValue: T {
    get { self.store.get(atom: self.atom) }
    nonmutating set { self.store.set(atom: self.atom, value: newValue) }
  }

  public var projectedValue: Binding<T> {
    Binding(
      get: { wrappedValue },
      set: { wrappedValue = $0 }
    )
  }
}

@propertyWrapper
public struct AtomValue<T: Equatable>: DynamicProperty {
  @StateObject private var model: ValueModel<T>
  private let store: JotaiStore
  private let atom: Atom<T>

  public init(_ atom: Atom<T>, store maybeStore: JotaiStore? = nil) {
    self.atom = atom
    self.store = maybeStore ?? JotaiStore.shared
    let valueModel = ValueModel(value: store.get(atom: atom))
    valueModel.listen(store: store, atom: atom)
    self._model = StateObject(wrappedValue: valueModel)
  }

  public var wrappedValue: T {
    self.store.get(atom: self.atom)
  }
}
