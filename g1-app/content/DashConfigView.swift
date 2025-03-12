import EventKit
import Log
import SwiftData
import SwiftUI

struct DashConfigView: View {
  @StateObject var vm: MainVM
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \NoteModel.persistentModelID) private var notes: [NoteModel]
  @State var reminderList: EKCalendar?

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
        if let currentReminderList = vm.connectionManager.getReminderList() {
          let selectedReminderList: Binding<EKCalendar?> = Binding(
            get: {
              reminderList = currentReminderList
              return reminderList
            },
            set: {
              guard let identifier = $0?.calendarIdentifier else { return }
              vm.connectionManager.setReminderList(identifier)
              reminderList = $0
            }
          )
          Picker("Reminders", selection: selectedReminderList) {
            ForEach(reminderLists, id: \.calendarIdentifier) { list in
              Text(list.title)
                .tag(list)
            }
          }
          .onChange(of: reminderList) {
            vm.connectionManager.syncReminders()
          }
        }

        let maxNote =
          notes.lastIndex(where: { note in note.title.count > 0 || note.text.count > 0 }) ?? -1
        ForEach(notes) { note in
          if let noteIndex = notes.firstIndex(of: note) {
            if min(maxNote + 1, 3) >= noteIndex {
              NavigationLink {
                NoteEditView(note: note)
                  .onDisappear {
                    vm.connectionManager.dashNotes(notes: notes[0...maxNote].map { $0.toG1Cmd() })
                  }
              } label: {
                if maxNote < noteIndex {
                  Label("Add", systemImage: "plus.circle.fill")
                } else {
                  Text(note.title)
                }
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if maxNote >= noteIndex {
                  Button(role: .destructive) {
                    modelContext.delete(note)
                    modelContext.insert(NoteModel())
                    try? modelContext.save()
                  } label: {
                    Label("Delete", systemImage: "trash")
                  }
                }
              }
            }
          }
        }
        // .padding().textFieldStyle(.roundedBorder)
        // .frame(height: 100)
        // .scrollContentBackground(.hidden)
        // .background(Color(red: 0.1, green: 0.1, blue: 0.1))
      }
      .onAppear {
        if notes.count < 4 {
          log("inserting notes")
          for _ in notes.count..<4 {
            modelContext.insert(NoteModel())
          }
          try? modelContext.save()
        }
      }
      Section(header: Text("Calendar")) {
        Button("Dash calendar") {
          vm.connectionManager.dashCalendar()
        }
        .buttonStyle(.bordered)
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
