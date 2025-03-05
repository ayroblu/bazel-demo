import EventKit
import Log
import SwiftUI

extension ConnectionManager {
  func requestCalendarAccessIfNeeded() {
    let authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    if authorizationStatus == .fullAccess {
      addListener()
      syncEvents()
      return
    }
    guard authorizationStatus == .notDetermined else { return }
    Task {
      let result = try? await eventStore.requestFullAccessToEvents()
      log("request calendar access result: \(String(describing: result))")
      if result == true {
        addListener()
        syncEvents()
      }
    }
  }

  private func addListener() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(self.storeChanged), name: .EKEventStoreChanged, object: eventStore)
  }

  private func fetchEvents() -> [EKEvent] {
    let now = Date()
    let nextWeek = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)!
    let predicate = eventStore.predicateForEvents(withStart: now, end: nextWeek, calendars: nil)
    let fetchedEvents = eventStore.events(matching: predicate)

    return fetchedEvents
  }

  func syncEvents() {
    if let event = fetchEvents().first {
      let time = dateToText(startDate: event.startDate, endDate: event.endDate)
      let configEvent = G1Cmd.Config.Event(
        name: event.title, time: time, location: event.location ?? "")
      let data = G1Cmd.Config.calendarData(event: configEvent)
      manager.transmitBoth(data)
    } else {
      manager.transmitBoth(
        G1Cmd.Config.calendarData(
          event: G1Cmd.Config.Event(name: "No events", time: "", location: "")))
    }
  }

  @objc
  private func storeChanged() {
    log("Store changed")
    syncEvents()
  }

  private func dateToText(startDate: Date?, endDate: Date?) -> String {
    guard let startDate, let endDate else { return "" }
    let startTime = get24hTime(from: startDate)
    let endTime = get24hTime(from: endDate)
    let time = "\(startTime)-\(endTime)"
    if Calendar.current.isDateInToday(startDate) {
      return time
    } else if Calendar.current.isDateInTomorrow(startDate) {
      return "Tmr \(time)"
    } else {
      let day = getDayOfWeek(from: startDate)
      return "\(day) \(time)"
    }
  }
  private func getDayOfWeek(from date: Date) -> String {
    let formatter = DateFormatter()
    // "Mon", "Tue"
    formatter.dateFormat = "EEE"
    return formatter.string(from: date)
  }
  private func get24hTime(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
  private func get12hTime(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "hh:mm a"
    return formatter.string(from: date)
  }

  // Add a new event (example)
  // func addEvent(title: String, startDate: Date, endDate: Date) {
  //   let newEvent = EKEvent(eventStore: eventStore)
  //   newEvent.title = title
  //   newEvent.startDate = startDate
  //   newEvent.endDate = endDate
  //   newEvent.calendar = eventStore.defaultCalendarForNewEvents

  //   do {
  //     try eventStore.save(newEvent, span: .thisEvent)
  //     print("Event saved successfully")
  //     fetchEvents()  // Refresh the list
  //   } catch {
  //     print("Failed to save event: \(error.localizedDescription)")
  //   }
  // }
}
