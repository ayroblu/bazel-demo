import Log
import MapKit
import SwiftUI
import utils

let manager = ConnectionManager()

class MainVM: ObservableObject {
  @Published private var _text: String = "Hi there!"
  @Published var selection: TextSelection? = nil
  private var previous: String = ""
  var text: String {
    get {
      if let selection {
        let toSend = textWithCursor(text: _text, selection: selection)
        if toSend != previous {
          previous = toSend
          manager.sendText(toSend)
        }
      }
      return _text
    }
    set {
      _text = newValue
    }
  }

  var locationSub: (() -> Void)?
  var locationSubInner: (() -> Void)?
}

func textWithCursor(text: String, selection: TextSelection) -> String {
  var toSend = text
  switch selection.indices {
  case .selection(let range):
    if toSend.indices.contains(range.lowerBound) {
      toSend.insert("l", at: range.lowerBound)
    } else {
      toSend.append("l")
    }
    break
  default:
    break
  }
  return toSend
}

enum GlassesAppState {
  case Text
  case Navigation
  case Dash
  case Bmp
}
