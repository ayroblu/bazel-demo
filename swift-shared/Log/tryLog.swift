// Replaces usages of try? so that it logs the error before returning nil
public func tryLog<T>(_ scope: String, _ f: () throws -> T) -> T? {
  do {
    return try f()
  } catch {
    log(scope, error)
    return nil
  }
}
public func tryLog<T>(_ scope: String, _ f: () throws -> T?) -> T? {
  do {
    return try f()
  } catch {
    log(scope, error)
    return nil
  }
}
public func tryLog<T>(_ scope: String, _ f: () async throws -> T) async -> T? {
  do {
    return try await f()
  } catch {
    log(scope, error)
    return nil
  }
}
public func tryLog<T>(_ scope: String, _ f: () async throws -> T?) async -> T? {
  do {
    return try await f()
  } catch {
    log(scope, error)
    return nil
  }
}
