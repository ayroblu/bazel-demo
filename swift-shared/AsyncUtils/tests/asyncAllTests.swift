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

  func testAsyncAll_maxConcurrent() {
    let exp = expectation(description: "Async operation")

    Task {
      let firstResolvable = makeResolvable()
      let secondResolvable = makeResolvable()
      var counter1 = 0
      var counter2 = 0
      let funcList: [() async -> Int] = [
        {
          counter1 += 1
          let t = Task { @MainActor in
            return await firstResolvable.1()
          }
          try? await Task.sleep(for: .milliseconds(10))
          XCTAssertEqual(counter1, 1)
          XCTAssertEqual(counter2, 0)
          firstResolvable.0(1)
          return await t.value
        },
        {
          counter2 += 1
          let t = Task { @MainActor in
            return await secondResolvable.1()
          }
          try? await Task.sleep(for: .milliseconds(10))
          XCTAssertEqual(counter1, 1)
          XCTAssertEqual(counter2, 1)
          secondResolvable.0(2)
          return await t.value
        },
      ]
      let result = await asyncAll(funcList, maxConcurrent: 1)
      XCTAssertEqual(result, [1, 2])
      exp.fulfill()
    }

    wait(for: [exp], timeout: 1.0)
  }
}

func asyncFixture(_ value: Int) -> () async -> Int {
  return {
    return value
  }
}

func makeResolvable() -> ((Int) -> Void, () async -> Int) {
  var resolver: ((Int) -> Void)?

  return (
    { value in
      if resolver == nil {
        XCTFail("No resolver is set")
      }
      resolver?(value)
    },
    {
      await withCheckedContinuation { continuation in
        resolver = { value in
          continuation.resume(returning: value)
        }
      }
    }
  )
}
