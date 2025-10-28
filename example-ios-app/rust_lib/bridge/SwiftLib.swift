import RustBridge

public struct SwiftRust {
  public static func add(_ a: Int, _ b: Int) -> Int {
    Int(rust_add(Int32(a), Int32(b)))
  }
}
