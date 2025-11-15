import Foundation
import Jotai

@MainActor
public func atomWithTtl<T: Equatable>(ttlS: Double, _ f: @escaping (Getter) -> T) -> Atom<T> {
  let counterAtom = PrimitiveAtom(0)
  let taskAtom = PrimitiveAtom<Task<(), Error>?>(nil)
  return Atom { getter in
    let count = getter.get(atom: counterAtom)
    let task = getter.store.get(atom: taskAtom)
    task?.cancel()
    getter.store.set(
      atom: taskAtom,
      value: Task {
        defer { getter.store.set(atom: taskAtom, value: nil) }
        try await Task.sleep(for: .seconds(ttlS))
        getter.store.set(atom: counterAtom) { oldValue in
          return oldValue == count ? count + 1 : oldValue
        }
      })
    return f(getter)
  }
}
