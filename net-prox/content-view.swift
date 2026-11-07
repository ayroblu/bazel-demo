import SwiftUI
import proxy

struct ContentView: View {
  let model: ProxyModel

  var body: some View {
    VStack(spacing: 0) {
      header.padding()
      Divider()
      HSplitView {
        clientList.frame(minWidth: 220, idealWidth: 260)
        requestTable.frame(minWidth: 560)
      }
    }
    .frame(minWidth: 820, minHeight: 420)
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        if let error = model.error {
          Text("Proxy stopped: \(error)").foregroundStyle(.red)
        } else {
          Text("On the other device set Wi-Fi › Configure Proxy › Manual to:")
          ForEach(model.addresses) { address in
            HStack(alignment: .firstTextBaseline) {
              Text("\(address.ip):\(String(model.port))")
                .font(.title3.monospaced())
                .textSelection(.enabled)
              Text(address.interface).foregroundStyle(.secondary)
            }
          }
        }
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 4) {
        HStack {
          Circle()
            .fill(model.upload + model.download > 0 ? Color.green : Color.secondary)
            .frame(width: 10, height: 10)
          Text("\(model.active) open")
        }
        Text("↑ \(rate(model.upload))   ↓ \(rate(model.download))").monospacedDigit()
      }
    }
  }

  private var clientList: some View {
    List(model.clients) { client in
      VStack(alignment: .leading, spacing: 2) {
        Text(model.name(of: client.id)).font(.headline)
        Text("\(client.id) · \(client.count) requests").foregroundStyle(.secondary)
        if let agent = client.userAgent {
          Text(agent).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
      }
    }
    .overlay {
      if model.clients.isEmpty {
        ContentUnavailableView("No traffic yet", systemImage: "network")
      }
    }
  }

  private var requestTable: some View {
    Table(model.snapshot.exchanges.reversed()) {
      TableColumn("Time") { Text($0.start, format: .dateTime.hour().minute().second()) }
        .width(70)
      TableColumn("Client") { Text(model.name(of: $0.client)) }
        .width(min: 80, ideal: 140)
      TableColumn("Method", value: \.method)
        .width(70)
      TableColumn("Host") { Text($0.target).help($0.userAgent ?? "") }
      TableColumn("Status") { exchange in
        Text(status(exchange))
          .foregroundStyle(failed(exchange) ? Color.red : Color.primary)
          .help(exchange.error ?? "")
      }
      .width(50)
      TableColumn("Up") { Text(bytes($0.sent)) }
        .width(70)
      TableColumn("Down") { Text(bytes($0.received)) }
        .width(70)
      TableColumn("Duration") { Text(duration($0)) }
        .width(70)
    }
  }
}

private func rate(_ bytesPerSecond: Int) -> String {
  "\(bytes(bytesPerSecond))/s"
}

private func status(_ exchange: Exchange) -> String {
  if let status = exchange.status { return String(status) }
  return exchange.end == nil ? "…" : "–"
}

private func failed(_ exchange: Exchange) -> Bool {
  guard let status = exchange.status else { return exchange.end != nil }
  return status >= 400
}

private func bytes(_ count: Int) -> String {
  Int64(count).formatted(.byteCount(style: .file))
}

private func duration(_ exchange: Exchange) -> String {
  guard let end = exchange.end else { return "" }
  let seconds = end.timeIntervalSince(exchange.start)
  return seconds < 1 ? "\(Int(seconds * 1000)) ms" : String(format: "%.1f s", seconds)
}
