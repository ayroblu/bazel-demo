import Foundation

@MainActor
public class JotaiStore {
  public static let shared = JotaiStore()

  private var map = [ObjectIdentifier: Any]()
  private var subs = [ObjectIdentifier: ClosureStore]()

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
    if !isStale, let cachedValue {
      return cachedValue.value
    }

    let getter = Getter(store: self)
    let value = atom.getValue(getter)
    map[key] = Value(value: value)

    depsManager.propagateDeps(atom: atom, tracked: getter.tracked)

    if isStale, let cachedValue, value == cachedValue.value {
      return value
    }

    subs[key]?.executeAll()

    return value
  }

  public func set<T: Equatable>(atom: PrimitiveAtom<T>, value: T) {
    let key = ObjectIdentifier(atom)
    if let cachedValue = map[key] as? Value<T>, value == cachedValue.value {
      return
    }
    map[key] = Value(value: value)

    depsManager.propagateStale(atom: atom, store: self)
    subs[key]?.executeAll()
  }
  public func set<T: Equatable, Arg>(atom: WritableAtom<T, Arg, Void>, value: Arg) {
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
      subs[key] = ClosureStore()
    }
    return subs[key, default: ClosureStore()].add(onChange)
  }
}

@MainActor
class DepsManager {
  // All the atoms that were "get"
  private var atomDeps = [ObjectIdentifier: [ObjectIdentifier: () -> Bool]]()
  // Reverse graph of atomDeps
  private var revDeps = [ObjectIdentifier: Set<ObjectIdentifier>]()
  // Reevaluate "stale" dependent atoms. If they changed, then discard cached value
  private var staleAtoms = [ObjectIdentifier: Set<ObjectIdentifier>]()

  func propagateDeps<T: Equatable>(atom: Atom<T>, tracked: [ObjectIdentifier: () -> Bool]) {
    let key = ObjectIdentifier(atom)
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
}

@MainActor
public class Atom<T: Equatable> {
  let getValue: (Getter) -> T
  public init(_ getValue: @escaping (Getter) -> T) {
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
}

public class WriteAtom<Arg, Result>: WritableAtom<Int, Arg, Result> {
  public init(setValue: @escaping (Setter, Arg) -> Result) {
    super.init(0, setValue)
  }
}

@MainActor
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
@MainActor
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

// @MainActor
// protocol AnyAtom {
//   associatedtype Value: Equatable
//   var getValue: (Getter) -> Value { get }
// }

class ClosureStore {
  private var closures: Set<UUID> = []
  private var closureMap: [UUID: () -> Void] = [:]

  func add(_ closure: @escaping () -> Void) -> () -> Void {
    let id = UUID()
    closures.insert(id)
    closureMap[id] = closure

    return { [weak self] in
      self?.closures.remove(id)
      self?.closureMap.removeValue(forKey: id)
    }
  }

  func executeAll() {
    closureMap.values.forEach { $0() }
  }
}
