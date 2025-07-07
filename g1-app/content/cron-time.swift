import Foundation
import Jotai
import Log
import g1protocol

class CronTimer {
  private var timer: Timer?

  func update() {
    let enabled = cronTimeEnabledState.get()
    if enabled {
      let intervalMinutes = cronTimeIntervalMinutesState.get()
      setTimer(minutes: intervalMinutes)
    } else {
      cancel()
    }
  }

  private func setTimer(minutes: Int) {
    timer?.invalidate()
    let interval = nextInterval(minutes: minutes)
    log("cron timer: setting timer for interval:", interval)
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { timer in
      log("cron timer: fired")
      self.setTimer(minutes: minutes)
      let isConnected = JotaiStore.shared.get(atom: isConnectedAtom)
      let isWearing = JotaiStore.shared.get(atom: glassesStateAtom) == .Wearing
      let isNotShowingApp = JotaiStore.shared.get(atom: glassesAppStateAtom) == nil
      guard isConnected && isWearing && isNotShowingApp else { return }
      log("cron timer: showing time")
      manager.showTime()
    }
  }
  private func cancel() {
    timer?.invalidate()
  }
}
let cronTimer = CronTimer()

private func nextInterval(minutes: Int) -> TimeInterval {
  let calendar = Calendar.current
  let now = Date()
  let nextDate = calendar.nextDate(
    after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime)!
  let endOfDayInterval = Int(nextDate.timeIntervalSince(now))
  let interval = Double(endOfDayInterval % (minutes * 60)) + 1

  return interval < 10 ? Double(minutes) * 60 + 1 : interval
}
