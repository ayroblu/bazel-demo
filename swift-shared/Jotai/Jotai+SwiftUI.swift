import Foundation
import SwiftUI

private class ValueModel<T: Equatable>: ObservableObject {
  @Published var value: T
  var dispose: (() -> Void)?
  init(value: T) {
    self.value = value
  }
  @MainActor
  func listen(store: JotaiStore, atom: Atom<T>) {
    dispose = store.sub(atom: atom) { [weak self, weak atom, weak store] in
      guard let self, let atom, let store else { return }
      // DispatchQueue: Publishing changes from within view updates is not allowed, this will cause undefined behavior
      DispatchQueue.main.async {
        self.value = store.get(atom: atom)
      }
    }
  }
  deinit {
    // TODO: write a test to validate this
    dispose?()
  }
}

@MainActor
@propertyWrapper
public struct AtomState<T: Equatable>: DynamicProperty {
  @StateObject private var model: ValueModel<T>
  private let store: JotaiStore
  private let atom: WritableAtom<T, T, Void>

  public init(
    wrappedValue defaultValue: T, _ atom: WritableAtom<T, T, Void>,
    // todo: why not store: JotaiStore = JotaiStore.shared? Maybe it caused a crash?
    store maybeStore: JotaiStore? = nil
  ) {
    self.init(atom, store: maybeStore)
    if let primitiveAtom = self.atom as? PrimitiveAtom<T> {
      self.store.set(atom: primitiveAtom, value: defaultValue)
    } else {
      self.store.set(atom: self.atom, value: defaultValue)
    }
  }
  public init(_ atom: WritableAtom<T, T, Void>, store maybeStore: JotaiStore? = nil) {
    self.atom = atom
    self.store = maybeStore ?? JotaiStore.shared
    let valueModel = ValueModel(value: store.get(atom: atom))
    valueModel.listen(store: store, atom: atom)
    self._model = StateObject(wrappedValue: valueModel)
  }

  public var wrappedValue: T {
    get { self.store.get(atom: self.atom) }
    nonmutating set {
      if let primitiveAtom = self.atom as? PrimitiveAtom<T> {
        self.store.set(atom: primitiveAtom, value: newValue)
      } else {
        self.store.set(atom: self.atom, value: newValue)
      }
    }
  }

  public var projectedValue: Binding<T> {
    Binding(
      get: { wrappedValue },
      set: { wrappedValue = $0 }
    )
  }
}

@MainActor
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

@MainActor
struct JotaiStoreKey: EnvironmentKey {
  static let defaultValue: JotaiStore = JotaiStore.shared
}

extension EnvironmentValues {
  @MainActor
  public var jotaiStore: JotaiStore {
    get { self[JotaiStoreKey.self] }
    set { self[JotaiStoreKey.self] = newValue }
  }
}

// @MainActor
// @Observable
// public class OnceAsyncAtomValue<T: Equatable> {
//   private let atom: WritableAtom<AsyncState<T>, Void, Void>
//   private let store: JotaiStore
//   private var isStarted: Bool = false
//   private var resolvedValue: T?
//   private var unsub: (() -> Void)?

//   public init(atom: WritableAtom<AsyncState<T>, Void, Void>, store: JotaiStore = JotaiStore.shared)
//   {
//     self.atom = atom
//     self.store = store
//   }

//   public var value: Async<T> {
//     if let resolvedValue {
//       unsub?()
//       return .resolved(value: resolvedValue)
//     } else if !isStarted {
//       isStarted = true
//       let value = store.get(atom: atom)
//       if case .resolved(let result) = value {
//         unsub?()
//         resolvedValue = result
//         return .resolved(value: result)
//       } else {
//         unsub = store.sub(atom: atom) { [self] in
//           let value = store.get(atom: atom)
//           if case .resolved(let result) = value {
//             unsub?()
//             resolvedValue = result
//           }
//         }
//       }
//     }
//     return .pending
//   }

//   public func invalidate() {
//     store.set(atom: atom, value: ())
//     unsub?()
//     unsub = nil
//     isStarted = false
//     resolvedValue = nil
//   }
// }
// public enum Async<T> {
//   case pending
//   case resolved(value: T)
// }
