import Foundation

func log(_ args: Any...) {
  let formatter = DateFormatter()
  formatter.dateFormat = "HH:mm:ss.SSS"  // Hours:Minutes:Seconds.Milliseconds

  let timeString = formatter.string(from: Date())

  print(timeString, terminator: " ")
  for arg in args {
    print(arg, terminator: " ")
  }
  print()
}
