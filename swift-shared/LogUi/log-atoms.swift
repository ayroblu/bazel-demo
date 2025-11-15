import Jotai
import Log
import LogDb

@MainActor
let selectLogsAtom: Atom<[LogModel]> = Atom { getter in
  (try? selectLog()) ?? []
}
@MainActor
func deleteAllLogsAndInvalidate() throws {
  try deleteAllLogs()
  defaultStore.invalidate(atom: selectLogsAtom)
}
@MainActor
func deleteOldLogsAndInvalidate() throws {
  try dropOldLog()
  defaultStore.invalidate(atom: selectLogsAtom)
}

@MainActor
var defaultStore: JotaiStore = JotaiStore.shared

public func logAtomEffect(_ logItem: LogItem) {
  logDbEffect(logItem)
  Task { @MainActor in
    defaultStore.invalidate(atom: selectLogsAtom)
  }
}
