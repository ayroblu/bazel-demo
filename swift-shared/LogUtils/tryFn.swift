import Log

public func tryFn<T>(f: () throws -> T) -> T? {
  do {
    return try f()
  } catch {
    log(error)
    return nil
  }
}
public func tryFn<T>(f: () throws -> T?) -> T? {
  do {
    return try f()
  } catch {
    log(error)
    return nil
  }
}
public func tryFn<T>(f: () async throws -> T) async -> T? {
  do {
    return try await f()
  } catch {
    log(error)
    return nil
  }
}
public func tryFn<T>(f: () async throws -> T?) async -> T? {
  do {
    return try await f()
  } catch {
    log(error)
    return nil
  }
}
