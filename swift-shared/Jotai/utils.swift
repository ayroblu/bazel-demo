import Foundation

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
class SubscriptionSet<Func> {
  private var closures: Set<Closure<Func>> = []
  var isEmpty: Bool {
    closures.isEmpty
  }
  var count: Int {
    closures.count
  }
  func sub(_ closure: Func) -> () -> Void {
    let closure = Closure(closure: closure)
    closures.insert(closure)
    return { [weak self] in
      self?.closures.remove(closure)
    }
  }
  func dispatch(_ f: (Func) -> Void) {
    for closure in closures {
      f(closure.closure)
    }
  }
}
