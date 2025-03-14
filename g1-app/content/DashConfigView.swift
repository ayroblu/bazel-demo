import EventKit
import Log
import SwiftData
import SwiftUI

struct DashConfigView: View {
  @StateObject var vm: MainVM
  @Environment(\.modelContext) private var modelContext
  @AppStorage(SELECTED_REMINDER_LIST) var reminderListId: String?

  var body: some View {
    List {
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
        let reminderLists = vm.connectionManager.getReminderLists()
        if let currentReminderList = vm.connectionManager.getReminderList(for: reminderListId) {
          let selectedReminderList: Binding<EKCalendar?> = Binding(
            get: { currentReminderList },
            set: {
              guard let identifier = $0?.calendarIdentifier else { return }
              vm.connectionManager.setReminderList(identifier)
            }
          )
          Picker("Reminders", selection: selectedReminderList) {
            ForEach(reminderLists, id: \.calendarIdentifier) { list in
              Text(list.title)
                .tag(list)
            }
          }
          .onChange(of: reminderListId) {
            vm.connectionManager.syncReminders()
          }
        }
      }
    }
  }
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
