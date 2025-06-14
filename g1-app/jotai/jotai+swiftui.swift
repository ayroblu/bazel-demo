import Foundation
import SwiftUI

@MainActor
@propertyWrapper
public class AtomValue<T: Equatable> {
  private let atom: Atom<T>
  private var value: T
  private var dispose: (() -> Void)?
  private var store: JotaiStore
  public init(_ atom: Atom<T>, store: JotaiStore? = nil) {
    self.atom = atom
    self.store = store ?? JotaiStore.shared
    self.value = self.store.get(atom: atom)
  }
  deinit {
    dispose?()
  }

  public var wrappedValue: T {
    if dispose == nil {
      dispose = store.sub(atom: atom) {
        self.value = self.store.get(atom: self.atom)
      }
    }
    return value
  }
}

@MainActor
@propertyWrapper
public class AtomState<T: Equatable> {
  private let atom: WritableAtom<T, T, Void>
  private var value: T
  private var dispose: (() -> Void)?
  private var store: JotaiStore
  public init(_ atom: WritableAtom<T, T, Void>, store: JotaiStore? = nil) {
    self.atom = atom
    self.store = store ?? JotaiStore.shared
    self.value = self.store.get(atom: atom)
  }
  deinit {
    dispose?()
  }

  public var wrappedValue: T {
    get {
      if dispose == nil {
        dispose = store.sub(atom: atom) {
          self.value = self.store.get(atom: self.atom)
        }
      }
      return value
    }
    set {
      store.set(atom: atom, value: newValue)
    }
  }
  public var projectedValue: Binding<T> {
    Binding(
      get: { self.wrappedValue },
      set: { newValue in self.wrappedValue = newValue }
    )
  }
}
