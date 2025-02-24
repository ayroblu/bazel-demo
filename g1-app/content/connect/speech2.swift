import AVFoundation
import Log
import Speech

actor SpeechRecognizer {
  private var recognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  var audioManager = AudioManager()

  // private var lastTranscription: SFTranscription?  // cache to make contrast between near results
  // private var cacheString = ""  // cache stream recognized formattedString

  @MainActor var transcript: String = ""

  enum RecognizerError: Error {
    case nilRecognizer
    case notAuthorizedToRecognize
    case notPermittedToRecord
    case recognizerIsUnavailable

    var message: String {
      switch self {
      case .nilRecognizer: return "Can't initialize speech recognizer"
      case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
      case .notPermittedToRecord: return "Not permitted to record audio"
      case .recognizerIsUnavailable: return "Recognizer is unavailable"
      }
    }
  }

  let callback: (String) -> Void
  init(callback: @escaping (String) -> Void) {
    self.callback = callback
    requestPermission()
  }
  nonisolated private func requestPermission() {
    Task {
      do {
        guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
          throw RecognizerError.notAuthorizedToRecognize
        }
        // guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
        //   throw RecognizerError.notPermittedToRecord
        // }
      } catch {
        log("SFSpeechRecognizer------permission error----\(error)")
      }
    }
  }

  nonisolated func startRecognition(locale: Locale) {
    Task {
      await startRecognitionInternal(locale: locale)
    }
  }

  private func startRecognitionInternal(locale: Locale) {
    audioManager.open()

    recognizer = SFSpeechRecognizer(locale: locale)
    guard let recognizer = recognizer else {
      log("Speech recognizer is not available")
      return
    }

    guard recognizer.isAvailable else {
      log("startRecognition recognizer is not available")
      return
    }

    let audioSession = AVAudioSession.sharedInstance()
    do {
      //try audioSession.setCategory(.record)
      try audioSession.setCategory(.playback, options: .mixWithOthers)
      try audioSession.setActive(true)
    } catch {
      log("Error setting up audio session: \(error)")
      return
    }

    recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
    guard let recognitionRequest = recognitionRequest else {
      log("Failed to create recognition request")
      return
    }
    recognitionRequest.shouldReportPartialResults = true  //true
    recognitionRequest.requiresOnDeviceRecognition = true

    recognitionTask = recognizer.recognitionTask(with: recognitionRequest) {
      [weak self] (result, error) in
      // self?.recognitionHandler(result: result, error: error)
      if let error = error {
        log("SpeechRecognizer Recognition error: \(error)")
      } else if let result = result {
        // result.isFinal?
        self?.transcribe(result.bestTranscription.formattedString)
      }
    }
  }

  nonisolated private func recognitionHandler(
    result: SFSpeechRecognitionResult?, error: Error?
  ) {
    if let error = error {
      log("SpeechRecognizer Recognition error: \(error)")
    } else if let result = result {
      // result.isFinal?

      transcribe(result.bestTranscription.formattedString)

      // let currentTranscription = result.bestTranscription
      // if lastTranscription == nil {
      //   cacheString = currentTranscription.formattedString
      // } else {

      //   if currentTranscription.segments.count < lastTranscription?.segments.count ?? 1
      //     || currentTranscription.segments.count == 1
      //   {
      //     self.lastRecognizedText += cacheString
      //     cacheString = ""
      //   } else {
      //     cacheString = currentTranscription.formattedString
      //   }
      // }

      // lastTranscription = result.bestTranscription
    }
  }

  nonisolated func stopRecognition() {
    Task {
      await reset()
    }
  }

  private func reset() {
    audioManager.close()
    recognitionTask?.cancel()
    try? AVAudioSession.sharedInstance().setActive(false)
    recognitionRequest = nil
    recognitionTask = nil
    recognizer = nil
  }

  nonisolated func appendPcmData(_ pcmData: Data) {
    Task {
      await appendPcmDataInner(pcmData)
    }
  }

  func appendPcmDataInner(_ pcmData: Data) {
    guard let recognitionRequest = recognitionRequest else {
      log("Recognition request is not available")
      return
    }

    let audioFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
    guard
      let audioBuffer = AVAudioPCMBuffer(
        pcmFormat: audioFormat,
        frameCapacity: AVAudioFrameCount(pcmData.count)
          / audioFormat.streamDescription.pointee.mBytesPerFrame)
    else {
      log("Failed to create audio buffer")
      return
    }
    audioBuffer.frameLength = audioBuffer.frameCapacity

    audioManager.write(audioBuffer: audioBuffer)

    pcmData.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
      if let audioDataPointer = bufferPointer.baseAddress?.assumingMemoryBound(to: Int16.self) {
        let audioBufferPointer = audioBuffer.int16ChannelData?.pointee
        audioBufferPointer?.initialize(
          from: audioDataPointer, count: pcmData.count / MemoryLayout<Int16>.size)
        recognitionRequest.append(audioBuffer)
      } else {
        log("Failed to get pointer to audio data")
      }
    }
  }

  nonisolated private func transcribe(_ message: String) {
    Task { @MainActor in
      log("Message", message)
      transcript = message
      await callback(message)
    }
  }
  nonisolated private func transcribe(_ error: Error) {
    var errorMessage = ""
    if let error = error as? RecognizerError {
      errorMessage += error.message
    } else {
      errorMessage += error.localizedDescription
    }
    Task { @MainActor [errorMessage] in
      transcript = "<< \(errorMessage) >>"
    }
  }
}
