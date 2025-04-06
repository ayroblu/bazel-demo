public func runWhileSubbed(start: @escaping () -> Void, stop: @escaping () -> Void) -> () -> () ->
  Void
{
  var counter = 0
  return {
    if counter == 0 {
      start()
    }
    counter += 1
    return {
      counter -= 1
      if counter == 0 {
        stop()
      }
    }
  }
}
