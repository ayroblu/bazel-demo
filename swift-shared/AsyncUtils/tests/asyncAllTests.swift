import AsyncUtils
import XCTest

class AsyncAllTests: XCTestCase {
  func testAsyncAll_Success() async {
    let funcList = (1..<10).map { asyncFixture($0) }
    let result = await asyncAll(funcList)
    XCTAssertEqual(result, Array(1..<10))
  }

  func testAsyncAll_pastMaxSuccess() async {
    let funcList = (1..<10).map { asyncFixture($0) }
    let result = await asyncAll(funcList, maxConcurrent: 5)
    XCTAssertEqual(result, Array(1..<10))
  }

  func testAsyncAll_maxConcurrent() async {
    let running = Running()
    let funcList: [@Sendable () async -> Int] = (1...3).map { value in
      {
        await running.enter()
        try? await Task.sleep(for: .milliseconds(10))
        await running.exit()
        return value
      }
    }
    let result = await asyncAll(funcList, maxConcurrent: 1)
    XCTAssertEqual(result, [1, 2, 3])
    let maxRunning = await running.max
    XCTAssertEqual(maxRunning, 1)
  }
}

func asyncFixture(_ value: Int) -> @Sendable () async -> Int {
  return {
    return value
  }
}

actor Running {
  private var current = 0
  private(set) var max = 0

  func enter() {
    current += 1
    max = Swift.max(max, current)
  }

  func exit() {
    current -= 1
  }
}
