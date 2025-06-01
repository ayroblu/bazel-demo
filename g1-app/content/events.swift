import EventKit
import Log
import SwiftUI
import utils

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
    if let event = fetchEvents().filter({ !$0.isAllDay }).first {
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

extension ConnectionManager {
  func requestReminderAccessIfNeeded() {
    let authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    if authorizationStatus == .fullAccess {
      addReminderListener()
      syncReminders()
      return
    }
    guard authorizationStatus == .notDetermined else { return }
    Task {
      let result = try? await eventStore.requestFullAccessToReminders()
      log("request reminders access result: \(String(describing: result))")
      if result == true {
        addReminderListener()
        syncReminders()
      }
    }
  }

  private func addReminderListener() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(self.storeChangedReminders), name: .EKEventStoreChanged,
      object: eventStore)
  }

  @objc
  private func storeChangedReminders() {
    log("Store changed reminders")
    syncReminders()
  }

  func syncReminders() {
    let authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    guard authorizationStatus == .fullAccess else { return }
    Task {
      let selectedReminders = await fetchSelectedReminders()
      let notes = selectedReminders.map {
        let text = $0.reminders.prefix(4).map { $0.title.prefix(50) }.joined(separator: "\n")
        return G1Cmd.Config.Note(title: String($0.list.title.prefix(50)), text: text)
      }
      dashNotes(notes: notes)
    }
  }

  func getReminderLists() -> [EKCalendar] {
    return eventStore.calendars(for: .reminder)
  }

  func getSelectedReminderLists() -> [EKCalendar] {
    let listIds = ReminderListsState.get()
    guard let listIds else {
      return [eventStore.defaultCalendarForNewReminders()].compactMap { $0 }
    }
    let selectedCalendars = listIds.uniqued().compactMap { getReminderList(for: $0) }
    guard selectedCalendars.count > 0 else {
      return [eventStore.defaultCalendarForNewReminders()].compactMap { $0 }
    }
    return selectedCalendars
  }

  private func getReminderList(for listId: String?) -> EKCalendar? {
    if let listId, let calendar = eventStore.calendar(withIdentifier: listId) {
      return calendar
    }
    return nil
  }

  func setReminderLists(_ value: [String]) {
    ReminderListsState.set(value)
  }

  private func fetchSelectedReminders() async -> [SelectedReminder] {
    let reminderLists = getSelectedReminderLists()
    return await asyncAll(
      reminderLists.map { list in
        return { [self] in
          let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [list])
          let reminders = await eventStore.fetchReminders(matching: predicate) ?? []
          return SelectedReminder(list: list, reminders: reminders)
        }
      })
  }
}

private struct SelectedReminder: Identifiable {
  let list: EKCalendar
  let reminders: [EKReminder]
  var id: String {
    list.calendarIdentifier
  }
}

extension EKEventStore {
  func fetchReminders(matching: NSPredicate) async -> [EKReminder]? {
    await withCheckedContinuation { continuation in
      fetchReminders(matching: matching) { reminders in
        continuation.resume(returning: reminders)
      }
    }
  }
}
