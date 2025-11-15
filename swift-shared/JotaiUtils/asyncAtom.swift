import Foundation
import Jotai

@MainActor
public func asyncAtom<T: Equatable & Sendable>(
  ttlS: Double? = nil, _ f: @MainActor @escaping (Getter) async throws -> T
) -> AsyncAtom<T> {
  let resolvedWithCacheAtom = PrimitiveAtom<T?>(nil)
  let resolvedAtom = PrimitiveAtom<T?>(nil)
  let resolvedErrorAtom = PrimitiveAtom<EquatableError?>(nil)
  let firstPending: AsyncState<T> = .pending()
  let valueAtom = PrimitiveAtom(asyncAtomInternal(ttlS: ttlS, f))
  let taskCacheAtom = PrimitiveAtom<Task<T, Error>?>(nil)
  let taskAtom = Atom { getter in
    getter.store.set(atom: resolvedAtom, value: nil)
    getter.store.set(atom: resolvedErrorAtom, value: nil)
    let task = getter.get(atom: getter.get(atom: valueAtom))
    getter.store.set(
      atom: taskCacheAtom,
      value: Task {
        do {
          let result = try await task.value
          getter.store.set(atom: resolvedAtom, value: result)
          getter.store.set(atom: resolvedWithCacheAtom, value: result)
          return result
        } catch {
          getter.store.set(atom: resolvedErrorAtom, value: EquatableError(underlying: error))
          throw error
        }
      })
    return task
  }
  return AsyncAtom(
    task: taskAtom,
    resolved: Atom { getter in getter.get(atom: resolvedAtom) },
    resolvedError: resolvedErrorAtom,
    resolvedWithCache: Atom { getter in
      _ = getter.get(atom: taskAtom)
      return getter.get(atom: resolvedWithCacheAtom)
    },
    state: Atom { getter in
      _ = getter.get(atom: taskAtom)
      let resolved = getter.get(atom: resolvedAtom)
      let resolvedState: AsyncState<T> = resolved == nil ? firstPending : .resolved(data: resolved!)
      return resolvedState
    },
    reset: WriteAtom { (setter, _) in
      setter.set(atom: resolvedAtom, value: nil)
      setter.set(atom: resolvedWithCacheAtom, value: nil)
      setter.set(atom: valueAtom, value: asyncAtomInternal(ttlS: ttlS, f))
    }
  )
}

@MainActor
func asyncAtomInternal<T: Equatable>(
  ttlS: Double? = nil,
  _ f: @escaping (Getter) async throws -> T
) -> Atom<Task<T, Error>> {
  if let ttlS {
    return atomWithTtl(ttlS: ttlS) { (getter) in
      return Task {
        return try await f(getter)
      }
    }
  }
  return Atom { (getter) in
    return Task {
      return try await f(getter)
    }
  }
}

public class AsyncAtom<T: Equatable & Sendable>: Equatable {
  public let task: Atom<Task<T, Error>>
  public let resolvedError: Atom<EquatableError?>
  public let resolved: Atom<T?>
  public let resolvedWithCache: Atom<T?>
  public let state: Atom<AsyncState<T>>
  public let reset: WriteAtom<(), ()>
  public init(
    task: Atom<Task<T, Error>>, resolved: Atom<T?>, resolvedError: Atom<EquatableError?>,
    resolvedWithCache: Atom<T?>,
    state: Atom<AsyncState<T>>, reset: WriteAtom<(), ()>
  ) {
    self.task = task
    self.resolved = resolved
    self.resolvedError = resolvedError
    self.resolvedWithCache = resolvedWithCache
    self.state = state
    self.reset = reset
  }
  public static func == (lhs: AsyncAtom<T>, rhs: AsyncAtom<T>) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
  }
}

public enum AsyncState<T: Equatable>: Equatable {
  case pending(id: UUID = UUID())
  case resolved(data: T)

  public static func == (lhs: AsyncState<T>, rhs: AsyncState<T>) -> Bool {
    switch (lhs, rhs) {
    case (.pending(let id1), .pending(let id2)):
      return id1 == id2
    case (.resolved(let data1), .resolved(let data2)):
      return data1 == data2
    default:
      return false
    }
  }
}

public struct EquatableError: Equatable {
  let underlying: Error

  public static func == (lhs: EquatableError, rhs: EquatableError) -> Bool {
    return (lhs.underlying as NSError) == (rhs.underlying as NSError)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine((underlying as NSError).code)
    hasher.combine((underlying as NSError).domain)
  }
}
