import Jotai
import JotaiUtils
import SwiftUI

public struct JotaiExampleView: View {
  public init() {}
  @State var key: String = "first"
  public var body: some View {
    JotaiCounterView(atom: counterAtom(key))
      .id(counterAtom(key))
      .onAppear {
        Task {
          try await Task.sleep(for: .seconds(2))
          key = "second"
        }
      }
  }
}

struct JotaiCounterView: View {
  @AtomValue var counter: Int
  private let atom: PrimitiveAtom<Int>
  @State var task: Task<(), Error>?

  init(atom: PrimitiveAtom<Int>) {
    _counter = AtomValue(atom)
    self.atom = atom
  }
  var body: some View {
    Text("JotaiExample counter: \(counter)")
      .onAppear {
        task = Task {
          for i in 1..<10 {
            try await Task.sleep(for: .seconds(1))
            JotaiStore.shared.set(atom: atom, value: i)
          }
        }
      }
      .onDisappear {
        task?.cancel()
      }
  }
}

let counterAtom = atomFamily { (key: String) in PrimitiveAtom(0) }
