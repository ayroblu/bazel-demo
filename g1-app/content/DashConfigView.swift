import EventKit
import Log
import SwiftData
import SwiftUI
import jotai

struct DashConfigView: View {
  @StateObject var vm: MainVM
  @Environment(\.modelContext) private var modelContext
  @State var forceRerender = 0
  @AtomState(notifDirectPushAtom) var notifDirectPush: Bool
  @AtomState(notifDurationSecondsDoubleAtom) var notifDurationSeconds: Double
  @AtomState(notifConfigCalendarAtom) var calendarEnabled: Bool
  @AtomState(notifConfigCallAtom) var callEnabled: Bool
  @AtomState(notifConfigMsgAtom) var msgEnabled: Bool
  @AtomState(notifConfigIosMailAtom) var iosMailEnabled: Bool
  @AtomState(notifConfigAppsAtom) var appsEnabled: Bool

  var body: some View {
    List {
      let headsUpAngle = Binding(
        get: { Double(vm.headsUpAngle) },
        set: { vm.headsUpAngle = UInt8($0) }
      )
      Section(header: Text("Dash angle: \(vm.headsUpAngle)°")) {
        Slider(
          value: headsUpAngle,
          in: 0...60,
          step: 1
        ) { editing in
          if !editing {
            vm.connectionManager.headsUpAngle(angle: vm.headsUpAngle)
          }
        }
      }

      let dashVertical = Binding(
        get: { Double(vm.dashVertical) },
        set: {
          vm.dashVertical = UInt8($0)
          vm.connectionManager.dashPosition(
            isShow: true, vertical: vm.dashVertical, distance: vm.dashDistance)
        }
      )
      Section(header: Text("Dash vertical: \(vm.dashVertical)")) {
        Slider(
          value: dashVertical,
          in: 1...8,
          step: 1
        ) { editing in
          if !editing {
            vm.connectionManager.dashPosition(
              isShow: editing, vertical: vm.dashVertical, distance: vm.dashDistance)
          }
        }
      }
      let dashDistance = Binding(
        get: { Double(vm.dashDistance) },
        set: {
          vm.dashDistance = UInt8($0)
          vm.connectionManager.dashPosition(
            isShow: true, vertical: vm.dashVertical, distance: vm.dashDistance)
        }
      )
      let dashDistanceLabel = NSString(format: "%.01f", Double(vm.dashDistance) / 2)
      Section(header: Text("Dash distance: \(dashDistanceLabel)m")) {
        Slider(
          value: dashDistance,
          in: 1...9,
          step: 1
        ) { editing in
          if !editing {
            vm.connectionManager.dashPosition(
              isShow: editing, vertical: vm.dashVertical, distance: vm.dashDistance)
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
        VStack {
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
  func toG1Cmd() -> G1Cmd.Config.Note {
    return G1Cmd.Config.Note(title: self.title, text: self.text)
  }
}
