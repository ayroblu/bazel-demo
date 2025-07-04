import Foundation

public func runWhileSubbed(start: @escaping () -> Void, stop: @escaping () -> Void) -> () -> () ->
  Void
{
  var counter = 0
  return {
    if counter == 0 {
      start()
    }
    counter += 1
    return {
      counter -= 1
      if counter == 0 {
        stop()
      }
    }
  }
}

struct Closure<Func>: Hashable {
  let id: UUID = UUID()
  let closure: Func

  static func == (lhs: Closure<Func>, rhs: Closure<Func>) -> Bool {
    return lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
public class SubscriptionSet<Func> {
  private var closures: Set<Closure<Func>> = []
  public init() {}
  public func sub(_ closure: Func) -> () -> Void {
    let closure = Closure(closure: closure)
    closures.insert(closure)
    return { [weak self] in
      self?.closures.remove(closure)
    }
  }
  public func dispatch(_ f: (Func) -> Void) {
    for closure in closures {
      f(closure.closure)
    }
  }
}

