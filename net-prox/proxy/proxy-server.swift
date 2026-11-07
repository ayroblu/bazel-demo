import Foundation
import Network

public struct Exchange: Sendable, Identifiable, Equatable {
  public let id: Int
  public let client: String
  public let method: String
  public let target: String
  public let userAgent: String?
  public let start: Date
  public var status: Int?
  public var sent = 0
  public var received = 0
  public var end: Date?
  public var error: String?
}

public struct Snapshot: Sendable, Equatable {
  public var exchanges: [Exchange] = []
  public var sent = 0
  public var received = 0
  public var failure: String?

  public init() {}
}

public final class ProxyServer: @unchecked Sendable {
  private let queue = DispatchQueue(label: "net-prox")
  private let listener: NWListener
  private var state = Snapshot()
  private var firstId = 0

  public init(port: UInt16) throws {
    listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
    listener.stateUpdateHandler = { [self] in
      if case .failed(let error) = $0 { state.failure = "\(error)" }
    }
    listener.newConnectionHandler = { [self] client in
      client.start(queue: queue)
      readHead(client, buffer: Data())
    }
    listener.start(queue: queue)
  }

  public func snapshot() -> Snapshot {
    queue.sync { state }
  }

  private func readHead(_ client: NWConnection, buffer: Data) {
    client.receive(minimumIncompleteLength: 1, maximumLength: maxChunk) {
      [self] data, _, isComplete, error in
      let buffer = buffer + (data ?? Data())
      if let end = buffer.range(of: headEnd) {
        handle(client, head: buffer[..<end.lowerBound], rest: buffer[end.upperBound...])
      } else if error != nil || isComplete || buffer.count > maxChunk {
        client.cancel()
      } else {
        readHead(client, buffer: buffer)
      }
    }
  }

  private func handle(_ client: NWConnection, head: Data, rest: Data) {
    let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
    let request = lines[0].split(separator: " ").map(String.init)
    guard request.count == 3 else { return reply(client, "400 Bad Request") }
    let headers = Array(lines.dropFirst())
    let id = begin(
      client: client, method: request[0], target: request[1],
      userAgent: value(of: "user-agent", in: headers))
    if request[0] == "CONNECT" {
      tunnel(id, client, target: request[1], rest: rest)
    } else {
      forward(id, client, request: request, headers: headers, rest: rest)
    }
  }

  private func reply(_ client: NWConnection, _ status: String) {
    let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    client.send(content: Data(response.utf8), completion: .contentProcessed { _ in client.cancel() })
  }

  private func begin(client: NWConnection, method: String, target: String, userAgent: String?)
    -> Int
  {
    let id = firstId + state.exchanges.count
    state.exchanges.append(
      Exchange(
        id: id, client: address(of: client.endpoint), method: method, target: target,
        userAgent: userAgent, start: Date()))
    if state.exchanges.count > maxExchanges {
      state.exchanges.removeFirst()
      firstId += 1
    }
    return id
  }

  private func tunnel(_ id: Int, _ client: NWConnection, target: String, rest: Data) {
    guard let server = endpoint(target[...], defaultPort: 443) else {
      return reject(id, client, "400 Bad Request", error: "Bad target")
    }
    connect(id, client, to: server) { [self] server in
      update(id) { $0.status = 200 }
      client.send(
        content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .idempotent)
      relay(id, client, server, first: rest)
    }
  }

  private func forward(
    _ id: Int, _ client: NWConnection, request: [String], headers: [String], rest: Data
  ) {
    guard let scheme = request[1].range(of: "http://", options: [.anchored, .caseInsensitive])
    else { return reject(id, client, "400 Bad Request", error: "Not a proxy request") }
    let url = request[1][scheme.upperBound...]
    let slash = url.firstIndex(of: "/") ?? url.endIndex
    guard let server = endpoint(url[..<slash], defaultPort: 80) else {
      return reject(id, client, "400 Bad Request", error: "Bad target")
    }
    let path = slash == url.endIndex ? "/" : String(url[slash...])
    let kept = headers.filter { !hopByHop.contains(headerName($0)) }
    let head = (["\(request[0]) \(path) \(request[2])"] + kept + ["Connection: close", "", ""])
      .joined(separator: "\r\n")
    connect(id, client, to: server) { [self] server in
      relay(id, client, server, first: Data(head.utf8) + rest)
    }
  }

  private func reject(_ id: Int, _ client: NWConnection, _ status: String, error: String) {
    update(id) {
      $0.status = Int(status.prefix(3))
      $0.end = Date()
      $0.error = error
    }
    reply(client, status)
  }

  private func connect(
    _ id: Int, _ client: NWConnection, to endpoint: NWEndpoint,
    onReady: @escaping @Sendable (NWConnection) -> Void
  ) {
    let server = NWConnection(to: endpoint, using: .tcp)
    server.stateUpdateHandler = { [self] state in
      switch state {
      case .ready:
        server.stateUpdateHandler = nil
        onReady(server)
      case .waiting(let error), .failed(let error):
        server.stateUpdateHandler = nil
        server.cancel()
        reject(id, client, "502 Bad Gateway", error: "\(error)")
      default:
        break
      }
    }
    server.start(queue: queue)
  }

  private func update(_ id: Int, _ change: (inout Exchange) -> Void) {
    let index = id - firstId
    if index >= 0 { change(&state.exchanges[index]) }
  }

  private func relay(_ id: Int, _ client: NWConnection, _ server: NWConnection, first: Data) {
    let open = Counter(2)
    count(id, first, upstream: true)
    server.send(
      content: first,
      completion: .contentProcessed { [self] error in
        if let error { return finish(id, client, server, error) }
        pump(id, from: client, to: server, upstream: true, open: open)
      })
    pump(id, from: server, to: client, upstream: false, open: open)
  }

  private func count(_ id: Int, _ data: Data, upstream: Bool) {
    if upstream { state.sent += data.count } else { state.received += data.count }
    update(id) { exchange in
      if upstream {
        exchange.sent += data.count
        return
      }
      if exchange.status == nil { exchange.status = statusCode(data) }
      exchange.received += data.count
    }
  }

  private func finish(_ id: Int, _ a: NWConnection, _ b: NWConnection, _ error: NWError?) {
    a.cancel()
    b.cancel()
    update(id) { exchange in
      guard exchange.end == nil else { return }
      exchange.end = Date()
      exchange.error = error.map { "\($0)" }
    }
  }

  private func pump(
    _ id: Int, from: NWConnection, to: NWConnection, upstream: Bool, open: Counter
  ) {
    from.receive(minimumIncompleteLength: 1, maximumLength: maxChunk) {
      [self] data, _, isComplete, error in
      if let error { return finish(id, from, to, error) }
      if let data { count(id, data, upstream: upstream) }
      to.send(
        content: data, contentContext: isComplete ? .finalMessage : .defaultMessage,
        completion: .contentProcessed { [self] error in
          if let error { return finish(id, from, to, error) }
          if !isComplete { return pump(id, from: from, to: to, upstream: upstream, open: open) }
          open.value -= 1
          if open.value == 0 { finish(id, from, to, nil) }
        })
    }
  }
}

private let maxChunk = 65536
private let maxExchanges = 1000
private let headEnd = Data("\r\n\r\n".utf8)
private let hopByHop: Set = ["connection", "keep-alive", "proxy-connection", "proxy-authorization"]

private func value(of name: String, in headers: [String]) -> String? {
  headers.first { headerName($0) == name }?
    .split(separator: ":", maxSplits: 1).dropFirst().first?
    .trimmingCharacters(in: .whitespaces)
}

private func headerName(_ line: String) -> String {
  line.prefix { $0 != ":" }.lowercased()
}

private func address(of endpoint: NWEndpoint) -> String {
  guard case .hostPort(let host, _) = endpoint else { return "\(endpoint)" }
  if case .ipv6(let ip) = host, let v4 = ip.asIPv4 { return "\(v4)" }
  return String("\(host)".split(separator: "%")[0])
}

private func endpoint(_ authority: Substring, defaultPort: Int) -> NWEndpoint? {
  guard let parts = URLComponents(string: "//\(authority)"), let host = parts.host, !host.isEmpty,
    let port = UInt16(exactly: parts.port ?? defaultPort).flatMap(NWEndpoint.Port.init(rawValue:))
  else { return nil }
  return .hostPort(host: .init(host), port: port)
}

private func statusCode(_ data: Data) -> Int? {
  String(decoding: data.prefix(12), as: UTF8.self).split(separator: " ").dropFirst().first
    .flatMap { Int($0) }
}

private final class Counter: @unchecked Sendable {
  var value: Int

  init(_ value: Int) {
    self.value = value
  }
}
