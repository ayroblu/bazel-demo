import SwiftUI

struct RouteBadge: View {
  let name: String

  var body: some View {
    Text(name)
      .font(.subheadline.bold())
      .monospacedDigit()
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .frame(minWidth: 44)
      .background(busRed, in: RoundedRectangle(cornerRadius: 4))
  }
}

func directionColor(_ direction: String) -> Color {
  direction == "inbound" ? .blue : busRed
}

func countdown(to date: Date, now: Date) -> String {
  let seconds = date.timeIntervalSince(now)
  return seconds < 60 ? "Due" : "\(Int(seconds / 60)) min"
}

let busRed = Color(red: 0.86, green: 0.14, blue: 0.12)
