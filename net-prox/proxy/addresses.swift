import Foundation

public struct LocalAddress: Sendable, Equatable, Identifiable {
  public let interface: String
  public let ip: String
  public var id: String { interface + ip }
}

public func localAddresses() -> [LocalAddress] {
  var list: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&list) == 0 else { return [] }
  defer { freeifaddrs(list) }
  var result: [LocalAddress] = []
  var item = list
  while let entry = item?.pointee {
    item = entry.ifa_next
    let flags = Int32(entry.ifa_flags)
    guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
      flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
    else { continue }
    var ip = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    getnameinfo(
      address, socklen_t(address.pointee.sa_len), &ip, socklen_t(ip.count), nil, 0, NI_NUMERICHOST)
    result.append(LocalAddress(interface: String(cString: entry.ifa_name), ip: string(ip)))
  }
  return result
}

@concurrent public func hostName(for ip: String) async -> String? {
  var hints = addrinfo()
  hints.ai_flags = AI_NUMERICHOST
  var info: UnsafeMutablePointer<addrinfo>?
  guard getaddrinfo(ip, nil, &hints, &info) == 0, let info else { return nil }
  defer { freeaddrinfo(info) }
  var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
  guard
    getnameinfo(
      info.pointee.ai_addr, info.pointee.ai_addrlen, &name, socklen_t(name.count), nil, 0,
      NI_NAMEREQD) == 0
  else { return nil }
  return string(name).trimmingCharacters(in: CharacterSet(charactersIn: "."))
}

private func string(_ chars: [CChar]) -> String {
  chars.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
}
