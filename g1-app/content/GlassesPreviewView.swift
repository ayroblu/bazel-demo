import SwiftUI

struct CustomCanvasView: View {
  var body: some View {
    Canvas { context, size in
      // Draw a custom line
      var path = Path()
      path.move(to: CGPoint(x: 20, y: 20))
      path.addLine(to: CGPoint(x: size.width - 20, y: 20))
      context.stroke(path, with: .color(.blue), lineWidth: 2)

      // Draw multiple lines
      // for i in 0..<5 {
      //   let y = CGFloat(60 + i * 20)
      //   path = Path()
      //   path.move(to: CGPoint(x: 20, y: y))
      //   path.addLine(to: CGPoint(x: size.width - 20, y: y))
      //   context.stroke(path, with: .color(.gray), lineWidth: 1)
      // }

      // Draw custom text
      let text = Text("Hello, Canvas!")
        .font(.system(size: 24, weight: .bold, design: .rounded))
      // .foregroundColor(.)

      context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
    }
    .frame(height: 100)
    .border(Color.gray)
    .padding()
  }
}
