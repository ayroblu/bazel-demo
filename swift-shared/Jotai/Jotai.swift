import Foundation

@MainActor
public class JotaiStore {
  public static let shared = JotaiStore()

  private var map = NSMapTable<AnyObject, AnyObject>(
    keyOptions: .weakMemory, valueOptions: .strongMemory)
  private var subs = [ObjectIdentifier: SubscriptionSet<() -> Void>]()

  let depsManager = DepsManager()

  public init() {}

  public func get<T: Equatable>(atom: Atom<T>) -> T {
    let key = ObjectIdentifier(atom)
    let isStale = depsManager.checkStale(key: key)

    let cachedValue = map.object(forKey: atom) as? Value<T>
    #if DEBUG
      if atom.isDebug {
        if let cachedValue {
          print("[jotai debug] get \(key) \(atom) Value(\(cachedValue.value)) isStale: \(isStale)")
        }
      }
    #endif
    if !isStale, let cachedValue {
      return cachedValue.value
    }

    let getter = Getter(store: self, key: key)
    depsManager.currentGetterId[key] = ObjectIdentifier(getter)
    depsManager.clearRevDeps(key: key)
    #if DEBUG
      getter.isDebug = atom.isDebug
    #endif
    let value = atom.getValue(getter)
    map.setObject(Value(value: value), forKey: atom)

    if isStale, let cachedValue, value == cachedValue.value {
      return value
    }

    if cachedValue != nil {
      if let closures = subs[key] {
        closures.dispatch { f in f() }
      }
    }

    return value
  }

  private func setPrimitive<T: Equatable>(atom: PrimitiveAtom<T>, value: T) {
    let key = ObjectIdentifier(atom)
    if let cachedValue = map.object(forKey: atom) as? Value<T>, value == cachedValue.value {
      return
    }
    #if DEBUG
      if atom.isDebug {
        let cachedValue = String(describing: map.object(forKey: atom))
        print("[jotai debug] set primitive key: \(key) Value(\(cachedValue)) newValue: \(value)")
      }
    #endif

    map.setObject(Value(value: value), forKey: atom)

    depsManager.propagateStale(key: key)

    if let closures = subs[key] {
      closures.dispatch { f in f() }
    }
  }
  public func set<T: Equatable>(atom: PrimitiveAtom<T>, value: T) {
    setPrimitive(atom: atom, value: value)
  }
  public func set<T: Equatable, Arg>(atom: WritableAtom<T, Arg, Void>, value: Arg) {
    #if DEBUG
      if atom.isDebug {
        print("[jotai debug] set Value(\(value))")
      }
    #endif
    if let atom = atom as? PrimitiveAtom<T> {
      // So that you can leverage the WritableAtom interface for primitives
      // print("invalid primitive atom in writable atom", atom, value)
      setPrimitive(atom: atom, value: value as! T)
      return
    }
    let setter = Setter(store: self, key: ObjectIdentifier(atom))
    atom.setValue(setter, value)
  }
  public func set<T: Equatable, Arg, Result>(atom: WritableAtom<T, Arg, Result>, value: Arg)
    -> Result
  {
    let setter = Setter(store: self, key: ObjectIdentifier(atom))
    let resultValue = atom.setValue(setter, value)
    return resultValue
  }
  public func set<T: Equatable>(atom: PrimitiveAtom<T>, valueFunc: (T) -> T) {
    set(atom: atom, value: valueFunc(get(atom: atom)))
  }

  public func sub<T: Equatable>(atom: Atom<T>, onChange: @escaping () -> Void) -> () -> Void {
    let key = ObjectIdentifier(atom)
    if subs[key] == nil {
      // Not sure why this is necessary, the default should have done it automatically
      subs[key] = SubscriptionSet()
    }
    let disposeDepsManager = depsManager.addSub(key: key, onStale: { let _ = self.get(atom: atom) })
    let disposeSubSet = subs[key, default: SubscriptionSet()].sub(onChange)

    // trigger getter on sub. It could alternatively be lazy, but no value for that
    let _ = get(atom: atom)

    return { [self] in
      disposeSubSet()
      if let closures = subs[key], closures.isEmpty {
        disposeDepsManager()
        subs[key] = nil
      }
    }
  }

  /// Removes the cached atom value from the cache
  public func invalidate<T: Equatable>(atom: Atom<T>) {
    let key = ObjectIdentifier(atom)
    map.removeObject(forKey: atom)
    depsManager.propagateStale(key: key)
    if let closures = subs[key] {
      closures.dispatch { f in f() }
    }
  }
}

class DepsManager {
  var currentGetterId = [ObjectIdentifier: ObjectIdentifier]()
  private var atomDeps = [ObjectIdentifier: [ObjectIdentifier: () -> Bool]]()
  // Reverse graph of atomDeps
  private var revDeps = [ObjectIdentifier: Set<ObjectIdentifier>]()
  // Reevaluate "stale" dependent atoms. If they changed, then discard cached value
  private var staleAtoms = [ObjectIdentifier: Set<ObjectIdentifier>]()
  // subs are reevaluated eagerly when stale deps are added
  private var subsHandlers = [ObjectIdentifier: () -> Void]()

  func clearRevDeps(key: ObjectIdentifier) {
    if let atomTrackedValues = atomDeps[key] {
      for t in atomTrackedValues.keys {
        revDeps[t]!.remove(key)
      }
    }
  }
  func updateDeps(
    key: ObjectIdentifier, tracked: [ObjectIdentifier: () -> Bool], getterId: ObjectIdentifier,
  ) {
    guard getterId == currentGetterId[key] else { return }
    atomDeps[key] = tracked
    for t in tracked.keys {
      revDeps[t, default: Set<ObjectIdentifier>()].insert(key)
    }
  }

  /// B -> A, C -> A. (means B and C depend on A)
  /// propagateStale(A)
  ///   seen: A
  ///   staleRevDep(A)
  ///     dep = [B, C]
  ///     staleAtoms[B] += A (and same for C)
  ///     recurse back to staleRevDep(B) and staleRevDep(C)
  ///     seen = [A, B, C]
  ///   get(A), get(B), get(C)
  func propagateStale(key: ObjectIdentifier) {
    var seenAtoms = Set<ObjectIdentifier>()
    seenAtoms.insert(key)
    func staleRevDep(atomKey: ObjectIdentifier) {
      for dep in revDeps[atomKey, default: Set<ObjectIdentifier>()] {
        guard !seenAtoms.contains(dep) else { continue }
        seenAtoms.insert(dep)
        staleAtoms[dep, default: Set<ObjectIdentifier>()].insert(atomKey)
        staleRevDep(atomKey: dep)
      }
    }
    staleRevDep(atomKey: key)
    for key in seenAtoms {
      subsHandlers[key]?()
    }
  }

  func checkStale(key: ObjectIdentifier) -> Bool {
    guard let staleDeps = staleAtoms[key] else { return false }
    guard !staleDeps.isEmpty else { return false }
    staleAtoms[key] = nil
    for dep in staleDeps {
      #if DEBUG
        if atomDeps[key]?[dep] == nil {
          print("Jotai: checkStale: missing f for dep \(dep) for key \(key)")
        }
      #endif
      if let f = atomDeps[key]?[dep], f() {
        return true
      }
    }
    return false
  }

  func addSub(key: ObjectIdentifier, onStale: @escaping () -> Void) -> () -> Void {
    subsHandlers[key] = onStale
    return { self.subsHandlers[key] = nil }
  }
}

class Value<T> {
  let value: T
  init(value: T) {
    self.value = value
  }
}

public class Atom<T: Equatable>: Equatable, Hashable {
  let getValue: (Getter) -> T
  public init(_ getValue: @escaping (Getter) -> T) {
    self.getValue = getValue
  }
  #if DEBUG
    public var isDebug: Bool = false
  #endif

  public static func == (lhs: Atom<T>, rhs: Atom<T>) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

public class WritableAtom<T: Equatable, Arg, Result>: Atom<T> {
  let setValue: (Setter, Arg) -> Result
  public init(_ defaultValue: T, _ setValue: @escaping (Setter, Arg) -> Result) {
    self.setValue = setValue
    super.init { _ in defaultValue }
  }
  public init(_ getValue: @escaping (Getter) -> T, _ setValue: @escaping (Setter, Arg) -> Result) {
    self.setValue = setValue
    super.init(getValue)
  }
}
public typealias SimpleWritableAtom<T: Equatable> = WritableAtom<T, T, Void>

public class PrimitiveAtom<T: Equatable>: SimpleWritableAtom<T> {
  public init(_ defaultValue: T) {
    super.init(defaultValue) { (store, value) in }
  }
  // You could add a special case where you pass in a setValue, and so if you self yourself in a set value, this is special cased to set the cached value
}

public class WriteAtom<Arg, Result>: WritableAtom<Int, Arg, Result> {
  public init(setValue: @escaping (Setter, Arg) -> Result) {
    super.init(0, setValue)
  }
}

@MainActor
public class Getter {
  public let store: JotaiStore
  let key: ObjectIdentifier
  #if DEBUG
    var isDebug: Bool = false
  #endif
  init(store: JotaiStore, key: ObjectIdentifier) {
    self.store = store
    self.key = key
  }
  var tracked: [ObjectIdentifier: () -> Bool] = [:]
  public func get<T: Equatable>(atom: Atom<T>) -> T {
    let value = store.get(atom: atom)
    tracked[ObjectIdentifier(atom)] = {
      let currentValue = self.store.get(atom: atom)
      #if DEBUG
        if self.isDebug || atom.isDebug {
          print("[jotai debug] tracked update: \(atom), currentValue: \(currentValue) != \(value)")
        }
      #endif
      return currentValue != value
    }
    #if DEBUG
      if self.isDebug || atom.isDebug {
        print(
          "[jotai debug] tracked adding: \(atom) \(key) -> \(ObjectIdentifier(atom)), currently: \(value)"
        )
      }
    #endif
    store.depsManager.updateDeps(
      key: key, tracked: tracked, getterId: ObjectIdentifier(self)
    )
    return value
  }
}
public class Setter: Getter {
  public func set<T: Equatable>(atom: PrimitiveAtom<T>, value: T) {
    store.set(atom: atom, value: value)
  }
  public func set<T: Equatable>(atom: PrimitiveAtom<T>, valueFunc: (T) -> T) {
    store.set(atom: atom, valueFunc: valueFunc)
  }
  public func set<T: Equatable, Arg>(atom: WritableAtom<T, Arg, Void>, value: Arg) {
    store.set(atom: atom, value: value)
  }
  public func set<T: Equatable, Arg, Result>(atom: WritableAtom<T, Arg, Result>, value: Arg)
    -> Result
  {
    return store.set(atom: atom, value: value)
  }
}
