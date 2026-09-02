import SwiftUI

struct SettingsView: View {
  @Bindable var store: StudyStore
  let speech: SpeechPlayer
  let languageCode: String
  let answerLanguageCode: String
  @Environment(\.dismiss) private var dismiss
  @State private var confirmingReset = false

  #if os(macOS)
    static let voiceDownloadHint =
      "Compact voices sound robotic. Add an enhanced or premium voice in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices, then pick it here."
  #else
    static let voiceDownloadHint =
      "Compact voices sound robotic. Add an enhanced or premium voice in Settings › Accessibility › Read & Speak › Voices (Spoken Content before iOS 26), then pick it here."
  #endif

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VoicePicker(title: "Question voice", languageCode: languageCode, speech: speech)
          VoicePicker(title: "Answer voice", languageCode: answerLanguageCode, speech: speech)
          VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Speaking speed") {
              Text(String(format: "%.1f×", store.speechRate))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Slider(
              value: $store.speechRate,
              in: StudyStore.speechRateRange,
              step: 0.1
            ) {
              Text("Speaking speed")
            } minimumValueLabel: {
              Text("slow").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
              Text("fast").font(.caption2).foregroundStyle(.secondary)
            }
            .labelsHidden()
            // The rate applies when playback next starts, matching how the voice picker behaves.
            .onChange(of: store.speechRate) { _, _ in speech.stop() }
          }
        } header: {
          Text("Voice")
        } footer: {
          Text(Self.voiceDownloadHint)
        }

        Section {
          Stepper(
            value: $store.browseQuestionRepeats,
            in: AutoBrowse.questionRepeatsRange
          ) {
            LabeledContent("Question repeats") {
              Text("\(store.browseQuestionRepeats)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        } header: {
          Text("Browse")
        } footer: {
          Text("Auto play reads the question this many times before the first answer.")
        }

        Section {
          LabeledContent("New cards per day") {
            TextField("", value: $store.newCardsPerDay, format: .number)
              .multilineTextAlignment(.trailing)
              .frame(width: 72)
              .accessibilityLabel("New cards per day")
              #if os(iOS)
                .keyboardType(.numberPad)
              #endif
          }
          LabeledContent("Maximum reviews per day") {
            TextField("", value: $store.reviewsPerDay, format: .number)
              .multilineTextAlignment(.trailing)
              .frame(width: 72)
              .accessibilityLabel("Maximum reviews per day")
              #if os(iOS)
                .keyboardType(.numberPad)
              #endif
          }
        } header: {
          Text("Study")
        } footer: {
          Text(
            "Unseen cards enter the queue up to this many per day, and every card the day "
              + "serves counts against the review limit.")
        }

        Section("Progress") {
          Button("Reset this deck's progress", role: .destructive) { confirmingReset = true }
            .confirmationDialog(
              "Reset progress for this deck?",
              isPresented: $confirmingReset,
              titleVisibility: .visible
            ) {
              Button("Reset progress", role: .destructive) {
                store.resetProgress()
                dismiss()
              }
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("Every card in this deck becomes new again. This cannot be undone.")
            }
        }

        Section("Deck format") {
          Text("The first CSV column name is the speech language code, such as ja. Add readings after Japanese words with brackets: 日本語[にほんご].")
        }
      }
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .frame(minWidth: 360, minHeight: 320)
  }
}

struct VoiceSettingsView: View {
  let speech: SpeechPlayer
  let languageCode: String
  let answerLanguageCode: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VoicePicker(title: "Question voice", languageCode: languageCode, speech: speech)
          VoicePicker(title: "Answer voice", languageCode: answerLanguageCode, speech: speech)
        } header: {
          Text("Voices")
        } footer: {
          Text(SettingsView.voiceDownloadHint)
        }
      }
      .navigationTitle("Voices")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .frame(minWidth: 360, minHeight: 260)
  }
}

private struct VoicePicker: View {
  let title: String
  let languageCode: String
  let speech: SpeechPlayer

  private var selection: Binding<String> {
    Binding(
      get: { speech.voices.voice(for: languageCode)?.identifier ?? "" },
      set: { identifier in
        speech.voices.select(identifier.isEmpty ? nil : identifier, for: languageCode)
        // The new voice applies to the next playback.
        speech.stop()
      }
    )
  }

  var body: some View {
    let voices = VoiceCatalog.voices(for: languageCode)
    if voices.isEmpty {
      Text("No installed voice speaks \(languageCode).")
    } else {
      Picker(title, selection: selection) {
        ForEach(voices, id: \.identifier) { voice in
          Text(VoiceCatalog.describe(voice)).tag(voice.identifier)
        }
      }
    }
  }
}
