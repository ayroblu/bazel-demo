import Foundation

private var globalId = 0

// TODO: thread safety
private func nextId() -> Int {
  globalId += 1
  return globalId
}

public class BaseAtom: Hashable {
  fileprivate let key: Int

  public var isReadOnly: Bool {
    fatalError("Not implemented")
  }

  public static func == (lhs: BaseAtom, rhs: BaseAtom) -> Bool {
    return lhs === rhs
  }

  init(key: Int) {
    self.key = key
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  fileprivate func _get(store: Store) -> Any {
    fatalError("Not implemented")
  }
}

@MainActor
public class Atom<T: Equatable>: BaseAtom {
  private let _isReadOnly: Bool
  fileprivate let getter: (Store) -> T
  fileprivate let onUpdate: ((T) -> Void)?

  public override var isReadOnly: Bool {
    return _isReadOnly
  }

  convenience public init(_ defaultValue: T) {
    self.init({ defaultValue }, nil)
  }

  public init(
    _ defaultValueGetter: @escaping () -> T,
    _ onUpdate: ((T) -> Void)?
  ) {
    let key = nextId()
    _isReadOnly = false
    self.getter = {
      return $0.getRaw(key: key, defaultValueGetter: defaultValueGetter)
    }
    self.onUpdate = onUpdate
    super.init(key: key)
  }

  public init(_ getter: @escaping (Store) -> T) {
    _isReadOnly = true
    self.getter = getter
    self.onUpdate = nil
    super.init(key: nextId())
  }

  override func _get(store: Store) -> Any {
    return getter(store)
  }
}

public protocol Subscriber {
  func receiveUpdate()
}

public class AnySubscriberBase: Subscriber, Hashable {
  public static func == (lhs: AnySubscriberBase, rhs: AnySubscriberBase) -> Bool {
    return lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  public func receiveUpdate() {
    fatalError("Not implemented")
  }
}

public class AnySubscriber<S>: AnySubscriberBase where S: Subscriber {
  public let subscriber: S

  public init(subscriber: S) {
    self.subscriber = subscriber
  }

  public override func receiveUpdate() {
    self.subscriber.receiveUpdate()
  }
}

public protocol Disposable {
  func dispose()
}

private struct ClosureSubscriber: Subscriber {
  let closure: () -> Void

  func receiveUpdate() {
    closure()
  }
}

private struct ClosureDisposable: Disposable {
  let closure: () -> Void

  func dispose() {
    closure()
  }
}

private class AtomInternals {
  let comparator: (Any, Any) -> Bool
  var value: Any?
  var memorizedValue: Any?
  var dependents = Set<BaseAtom>()
  var subscribers = Set<AnySubscriberBase>()

  init<T: Equatable>(value: T?) {
    self.comparator = { lhs, rhs in
      return (lhs as! T) == (rhs as! T)
    }
    self.value = value
  }
}

@MainActor
public class Store {
  public static let shared = Store()

  private var stateMap: [Int: AtomInternals] = [:]
  private var readScope: [BaseAtom] = []

  public func `get`<T: Equatable>(_ atom: Atom<T>) -> T {
    readScope.append(atom)
    defer {
      assert(readScope.popLast() != nil)
    }
    return atom.getter(self)
  }

  public func `set`<T: Equatable>(_ atom: Atom<T>, value: T) {
    guard !atom.isReadOnly else {
      // TODO: add strict mode to report the error.
      return
    }

    let key = atom.key
    if let internals = stateMap[key] {
      internals.value = value
    } else {
      stateMap[key] = .init(value: value)
    }
    atom.onUpdate?(value)
    triggerUpdate(for: key, newValue: value)
  }

  public func subscribe<T: Equatable, S: Subscriber>(atom: Atom<T>, subscriber: S) -> Disposable {
    // Get the atom's value once to track its dependencies.
    let _ = get(atom)

    let typeErasedSubscriber = AnySubscriber(subscriber: subscriber)

    let key = atom.key
    if let internals = stateMap[key] {
      internals.subscribers.insert(typeErasedSubscriber)
    } else {
      let internals = AtomInternals(value: nil as T?)
      internals.subscribers.insert(typeErasedSubscriber)
      stateMap[key] = internals
    }

    return ClosureDisposable {
      if let internals = self.stateMap[key] {
        internals.subscribers.remove(typeErasedSubscriber)
      }
    }
  }

  public func subscribe<T: Equatable>(atom: Atom<T>, action: @escaping () -> Void) -> Disposable {
    let subscriber = ClosureSubscriber(closure: action)
    return subscribe(atom: atom, subscriber: subscriber)
  }

  func getRaw<T: Equatable>(key: Int, defaultValueGetter: () -> T) -> T {
    let internals: AtomInternals
    if let _internals = stateMap[key] {
      internals = _internals
    } else {
      internals = .init(value: defaultValueGetter())
      stateMap[key] = internals
    }

    // Track the dependencies of this leaf atom.
    for dependent in readScope {
      guard dependent.key != key else {
        // Don't self-track.
        continue
      }

      internals.dependents.insert(dependent)
    }

    if let value = internals.value {
      return value as! T
    }
    let defaultValue = defaultValueGetter()
    internals.value = defaultValue
    return defaultValue
  }

  private func triggerUpdate(for key: Int, newValue: Any) {
    guard let internals = stateMap[key] else {
      return
    }

    if let memorizedValue = internals.memorizedValue {
      if internals.comparator(newValue, memorizedValue) {
        // Value is not changed.
        return
      }
    }
    internals.memorizedValue = newValue

    for subscriber in internals.subscribers {
      subscriber.receiveUpdate()
    }

    // Emit updates for dependents.
    for dependent in internals.dependents {
      let newDependentValue = dependent._get(store: self)
      triggerUpdate(for: dependent.key, newValue: newDependentValue)
    }
  }
}
