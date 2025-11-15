import Log
import Synchronization
import XCTest

class LogTests: XCTestCase {
  func testLog() {
    let effectLogMutex: Mutex<[LogItem]> = Mutex([])
    let effects: [LogEffect] = [
      { logItem in effectLogMutex.withLock { $0.append(logItem) } },
      { logItem in effectLogMutex.withLock { $0.append(logItem) } },
    ]
    registerLogEffects(effects: effects)
    log("Something")
    effectLogMutex.withLock { effectLog in
      XCTAssertEqual(effectLog.count, 2)
      XCTAssertEqual(effectLog[0].key, "I")
      XCTAssertEqual(effectLog[0].args as! [String], ["Something"])
    }
  }
}
