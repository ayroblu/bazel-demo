import Foundation

public class JotaiStore {
  public static let shared = JotaiStore()

  private var map = [ObjectIdentifier: Any]()
  private var subs = [ObjectIdentifier: SubscriptionSet<() -> Void>]()

  private let depsManager = DepsManager()

  public init() {}

  public func get<T: Equatable>(atom: Atom<T>) -> T {
    let key = ObjectIdentifier(atom)
    let isStale = depsManager.checkStale(key: key)

    let cachedValue = map[key] as? Value<T>
    #if DEBUG
      if atom.isDebug {
        if let cachedValue {
          print("[jotai debug] get", cachedValue, isStale)
        }
      }
    #endif
    if !isStale, let cachedValue, cachedValue.isValid() {
      return cachedValue.value
    }

    let getter = Getter(store: self)
    let value = atom.getValue(getter)
    map[key] = Value(value: value, expireTtl: atom.getExpireTtl())

    depsManager.propagateDeps(key: key, tracked: getter.tracked)

    if isStale, let cachedValue, value == cachedValue.value {
      return value
    }

    if let closures = subs[key] {
      closures.dispatch { f in f() }
    }

    return value
  }

  private func setPrimitive<T: Equatable>(atom: PrimitiveAtom<T>, value: T) {
    let key = ObjectIdentifier(atom)
    if let cachedValue = map[key] as? Value<T>, value == cachedValue.value {
      return
    }
    #if DEBUG
      if atom.isDebug {
        print("[jotai debug] set primitive", key, map[key] ?? "nil", "new value", value)
      }
    #endif
    map[key] = Value(value: value, expireTtl: atom.getExpireTtl())

    depsManager.propagateStale(atom: atom, store: self)
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
        print("[jotai debug] set", value)
      }
    #endif
    if let atom = atom as? PrimitiveAtom<T> {
      // This shouldn't happen except where there's a bug in type defs
      // For example a function that takes a WritableAtom, but you need override function to handle the PrimitiveAtom case
      print("invalid primitve atom in writable atom", atom, value)
      setPrimitive(atom: atom, value: value as! T)
      return
    }
    let setter = Setter(store: self)
    atom.setValue(setter, value)
  }
  public func set<T: Equatable, Arg, Result>(atom: WritableAtom<T, Arg, Result>, value: Arg)
    -> Result
  {
    let setter = Setter(store: self)
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
    return subs[key, default: SubscriptionSet()].sub(onChange)
  }
}

// Note that ideally we would isolate these to one thread, MainActor is a little heavy handed
class DepsManager {
  private var atomDeps = [ObjectIdentifier: [ObjectIdentifier: () -> Bool]]()
  // Reverse graph of atomDeps
  private var revDeps = [ObjectIdentifier: Set<ObjectIdentifier>]()
  // Reevaluate "stale" dependent atoms. If they changed, then discard cached value
  private var staleAtoms = [ObjectIdentifier: Set<ObjectIdentifier>]()

  func propagateDeps(key: ObjectIdentifier, tracked: [ObjectIdentifier: () -> Bool]) {
    if let atomTrackedValues = atomDeps[key] {
      for t in atomTrackedValues.keys {
        revDeps[t]!.remove(key)
      }
    }
    atomDeps[key] = tracked
    for t in tracked.keys {
      revDeps[t, default: Set<ObjectIdentifier>()].insert(key)
    }
  }

  func propagateStale<T: Equatable>(atom: Atom<T>, store: JotaiStore) {
    let key = ObjectIdentifier(atom)
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
  }

  func checkStale(key: ObjectIdentifier) -> Bool {
    guard let staleDeps = staleAtoms[key] else { return false }
    guard !staleDeps.isEmpty else { return false }
    staleAtoms[key] = nil
    for dep in staleDeps {
      if let f = atomDeps[key]?[dep], f() {
        return true
      }
    }
    return false
  }
}

struct Value<T> {
  let value: T
  let expireTtl: Date?
}
extension Value {
  func isValid() -> Bool {
    if let expireTtl {
      return expireTtl > Date()
    } else {
      return true
    }
  }
}
extension Atom {
  internal func getExpireTtl() -> Date? {
    if let ttlS {
      return Date().addingTimeInterval(ttlS)
    }
    return nil
  }
}

public class Atom<T: Equatable> {
  let getValue: (Getter) -> T
  let ttlS: Double?
  public init(ttlS: Double?, _ getValue: @escaping (Getter) -> T) {
    self.ttlS = ttlS
    self.getValue = getValue
  }
  public init(_ getValue: @escaping (Getter) -> T) {
    self.ttlS = nil
    self.getValue = getValue
  }
  #if DEBUG
    public var isDebug: Bool = false
  #endif
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

public class PrimitiveAtom<T: Equatable>: WritableAtom<T, T, Void> {
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

public class Getter {
  let store: JotaiStore
  init(store: JotaiStore) {
    self.store = store
  }
  var tracked: [ObjectIdentifier: () -> Bool] = [:]
  public func get<T: Equatable>(atom: Atom<T>) -> T {
    let value = store.get(atom: atom)
    tracked[ObjectIdentifier(atom)] = {
      return self.store.get(atom: atom) != value
    }
    return value
  }
}
public class Setter: Getter {
  public func set<T: Equatable>(atom: PrimitiveAtom<T>, value: T) {
    store.set(atom: atom, value: value)
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
