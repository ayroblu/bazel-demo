import SnapshotTesting
import XCTest

public func assertSnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record recording: Bool = false,
  timeout: TimeInterval = 5,
  file: StaticString = #file,
  testName: String = #function,
  line: UInt = #line
) {
  let snapshotDirectory = ProcessInfo.processInfo.environment["SNAPSHOT_REFERENCE_DIR"]!
  let failure = verifySnapshot(
    of: try value(),
    as: snapshotting,
    named: name,
    record: recording,
    snapshotDirectory: snapshotDirectory,
    timeout: timeout,
    file: file,
    testName: testName
  )
  guard let message = failure else { return }
  XCTFail(message, file: file, line: line)
}
