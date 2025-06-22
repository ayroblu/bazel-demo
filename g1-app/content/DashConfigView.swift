import EventKit
import Log
import SwiftData
import SwiftUI
import g1protocol
import jotai

let headsUpAngleDoubleAtom = DoubleUInt8CastAtom(atom: headsUpAngleAtom)
let dashVerticalDoubleAtom = DoubleUInt8CastAtom(atom: dashVerticalAtom) { (setter, newValue) in
  let dashVertical = setter.get(atom: dashVerticalAtom)
  let dashDistance = setter.get(atom: dashDistanceAtom)
  manager.dashPosition(isShow: true, vertical: dashVertical, distance: dashDistance)
}
let dashDistanceDoubleAtom = DoubleUInt8CastAtom(atom: dashDistanceAtom) { (setter, newValue) in
  let dashVertical = setter.get(atom: dashVerticalAtom)
  let dashDistance = setter.get(atom: dashDistanceAtom)
  manager.dashPosition(isShow: true, vertical: dashVertical, distance: dashDistance)
}
struct DashConfigView: View {
  @StateObject var vm: MainVM
  @Environment(\.modelContext) private var modelContext
  @State var forceRerender = 0
  @AtomState(dashVerticalAtom) var dashVertical: UInt8
  @AtomState(dashVerticalDoubleAtom) var dashVerticalDouble: Double
  @AtomState(dashDistanceAtom) var dashDistance: UInt8
  @AtomState(dashDistanceDoubleAtom) var dashDistanceDouble: Double
  @AtomState(headsUpAngleAtom) var headsUpAngle: UInt8
  @AtomState(headsUpAngleDoubleAtom) var headsUpAngleDouble: Double
  @AtomState(headsUpDashAtom) var headsUpDash: Bool
  @AtomState(notifDirectPushAtom) var notifDirectPush: Bool
  @AtomState(notifDurationSecondsDoubleAtom) var notifDurationSeconds: Double
  @AtomState(notifConfigCalendarAtom) var calendarEnabled: Bool
  @AtomState(notifConfigCallAtom) var callEnabled: Bool
  @AtomState(notifConfigMsgAtom) var msgEnabled: Bool
  @AtomState(notifConfigIosMailAtom) var iosMailEnabled: Bool
  @AtomState(notifConfigAppsAtom) var appsEnabled: Bool

  var body: some View {
    List {
      Section(header: Text("Heads up angle: \(headsUpAngle)°")) {
        Slider(
          value: $headsUpAngleDouble,
          in: 0...60,
          step: 1
        ) { editing in
          if !editing {
            manager.headsUpAngle(angle: headsUpAngle)
          }
        }
      }

      Toggle(isOn: $headsUpDash) {
        Text("Heads Up Dashboard")
      }

      if headsUpDash {
        Section(header: Text("Dash vertical: \(dashVertical)")) {
          Slider(
            value: $dashVerticalDouble,
            in: 1...8,
            step: 1
          ) { editing in
            if !editing {
              manager.dashPosition(isShow: editing, vertical: dashVertical, distance: dashDistance)
            }
          }
        }
        let dashDistanceLabel = NSString(format: "%.01f", Double(dashDistance) / 2)
        Section(header: Text("Dash distance: \(dashDistanceLabel)m")) {
          Slider(
            value: $dashDistanceDouble,
            in: 1...9,
            step: 1
          ) { editing in
            if !editing {
              manager.dashPosition(isShow: editing, vertical: dashVertical, distance: dashDistance)
            }
          }
        }
      }

      Section(header: Text("Notes")) {
        let selectedReminderLists = vm.connectionManager.getSelectedReminderLists()
        let reminderLists = vm.connectionManager.getReminderLists()
        var reminderListIds = selectedReminderLists.map { $0.calendarIdentifier }
        ForEach(selectedReminderLists, id: \.calendarIdentifier) { reminderList in
          if let idx = selectedReminderLists.firstIndex(of: reminderList) {
            let selectedReminderList: Binding<EKCalendar> = Binding(
              get: { reminderList },
              set: {
                let identifier = $0.calendarIdentifier
                if reminderListIds[safe: idx] != nil {
                  reminderListIds[idx] = identifier
                } else {
                  reminderListIds.append(identifier)
                }
                vm.connectionManager.setReminderLists(reminderListIds)
                forceRerender += 1
                vm.connectionManager.syncReminders()
              }
            )
            let pickerReminderLists = reminderLists.filter {
              !selectedReminderLists.contains($0) || reminderList == $0
            }
            Picker("\(idx + 1)", selection: selectedReminderList) {
              ForEach(pickerReminderLists, id: \.calendarIdentifier) { list in
                Text(list.title)
                  .tag(list)
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              if idx != 0 {
                Button(role: .destructive) {
                  reminderListIds.remove(at: idx)
                  vm.connectionManager.setReminderLists(reminderListIds)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
        }
        .id(forceRerender)
        let eligibleReminderLists = reminderLists.filter { !selectedReminderLists.contains($0) }
        if let nextReminderList = eligibleReminderLists.first, selectedReminderLists.count < 4 {
          Button("Add", systemImage: "plus.circle.fill") {
            reminderListIds.append(nextReminderList.calendarIdentifier)
            vm.connectionManager.setReminderLists(reminderListIds)
            forceRerender += 1
          }
        }
      }
      .environment(\.editMode, Binding.constant(EditMode.active))

      Section(header: Text("Notifications")) {
        Toggle(isOn: $notifDirectPush) {
          Text("Direct push")
        }
        VStack(alignment: .leading) {
          Text("Notification duration: \(Int(notifDurationSeconds)) seconds")
          Slider(value: $notifDurationSeconds, in: 5...20, step: 5) { editing in
            if !editing {
              manager.sendNotifConfig()
            }
          }
        }
        Toggle(isOn: $calendarEnabled) {
          Text("Calendar")
        }
        Toggle(isOn: $callEnabled) {
          Text("Calls")
        }
        Toggle(isOn: $msgEnabled) {
          Text("Messages")
        }
        Toggle(isOn: $iosMailEnabled) {
          Text("Mail")
        }
        Toggle(isOn: $appsEnabled) {
          Text("Apps")
        }
        NavigationLink("Apps") {
          LazyView {
            NotifAppsView(vm: vm)
          }
        }
        Button("Allow notifs") {
          vm.connectionManager.sendAllowNotifs()
        }
      }
    }
  }

  // .onMove(perform: move)
  // func move(from source: IndexSet, to destination: Int) {
  //     reminderLists.move(fromOffsets: source, toOffset: destination)
  // }
}

struct NoteEditView: View {
  @Bindable var note: NoteModel

  var body: some View {
    List {
      TextField("Enter title of note here...", text: $note.title)
      // ZStack cause: https://stackoverflow.com/questions/62620613/dynamic-row-hight-containing-texteditor-inside-a-list-in-swiftui
      ZStack {
        TextEditor(text: $note.text)
        Text(note.text).opacity(0).padding(.all, 8)
      }
    }
  }
}
extension NoteModel {
  func toG1Cmd() -> Config.Note {
    return Config.Note(title: self.title, text: self.text)
  }
}
