import SwiftUI

struct BusMarker: View {
  let heading: Double
  let color: Color

  var body: some View {
    Image(systemName: "arrow.up")
      .font(.system(size: 11, weight: .black))
      .foregroundStyle(.white)
      .rotationEffect(.degrees(heading))
      .frame(width: 22, height: 22)
      .background(color, in: Circle())
      .overlay(Circle().stroke(.black, lineWidth: 1.5))
  }
}

struct StopMarker: View {
  let letter: String?

  var body: some View {
    Group {
      if let letter, letter.count <= 2, !letter.contains("->") {
        Text(letter)
          .font(.system(size: 11, weight: .bold))
      } else {
        Image(systemName: "bus.fill")
          .font(.system(size: 10))
      }
    }
    .foregroundStyle(.white)
    .frame(width: 24, height: 24)
    .background(busRed, in: Circle())
    .overlay(Circle().stroke(.white, lineWidth: 1.5))
    .shadow(radius: 1)
  }
}

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
