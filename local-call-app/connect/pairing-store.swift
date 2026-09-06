import Foundation

/// A device this one has agreed to accept calls from. `peripheralId` is the
/// bluetooth handle for that device as seen by this device, cached so a paired
/// peer shows up as in range from a scan alone, without connecting to read its
/// identity again.
public nonisolated struct PairedPeer: Codable, Equatable, Identifiable {
  public let id: UUID
  /// What the device calls itself. It is refreshed from every call it places,
  /// so it cannot double as a name the user chose.
  public var name: String
  /// The name the user gave this device here, which wins when it is set.
  public var nickname: String?
  var secret: Data
  var peripheralId: UUID?

  public var displayName: String {
    guard let nickname, !nickname.isEmpty else { return name }
    return nickname
  }
}

nonisolated protocol PairingStorage: AnyObject {
  func pairingData(for key: String) -> Data?
  func setPairingData(_ data: Data?, for key: String)
}

nonisolated final class UserDefaultsPairingStorage: PairingStorage {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func pairingData(for key: String) -> Data? {
    defaults.data(forKey: key)
  }

  func setPairingData(_ data: Data?, for key: String) {
    defaults.set(data, forKey: key)
  }
}

nonisolated final class MemoryPairingStorage: PairingStorage {
  private var values: [String: Data] = [:]

  init() {}

  func pairingData(for key: String) -> Data? {
    values[key]
  }

  func setPairingData(_ data: Data?, for key: String) {
    values[key] = data
  }
}

nonisolated final class PairingStore {
  private let storage: PairingStorage
  private static let localIdKey = "connect.localId"
  private static let peersKey = "connect.pairedPeers"

  /// This device's stable identity in the signalling protocol. Bluetooth
  /// addresses rotate and peripheral handles differ per observer, so identity
  /// is carried in the messages instead.
  let localId: UUID
  private(set) var peers: [PairedPeer]

  init(storage: PairingStorage = UserDefaultsPairingStorage()) {
    self.storage = storage
    if let data = storage.pairingData(for: Self.localIdKey), let existing = UUID(
      uuidString: String(decoding: data, as: UTF8.self))
    {
      localId = existing
    } else {
      let created = UUID()
      storage.setPairingData(Data(created.uuidString.utf8), for: Self.localIdKey)
      localId = created
    }
    peers =
      storage.pairingData(for: Self.peersKey)
      .flatMap { try? JSONDecoder().decode([PairedPeer].self, from: $0) } ?? []
  }

  func peer(id: UUID) -> PairedPeer? {
    peers.first { $0.id == id }
  }

  func peer(peripheralId: UUID) -> PairedPeer? {
    peers.first { $0.peripheralId == peripheralId }
  }

  func secret(for id: UUID) -> Data? {
    peer(id: id)?.secret
  }

  func save(_ peer: PairedPeer) {
    if let index = peers.firstIndex(where: { $0.id == peer.id }) {
      peers[index] = peer
    } else {
      peers.append(peer)
    }
    persist()
  }

  func setPeripheralId(_ peripheralId: UUID, for id: UUID) {
    guard let index = peers.firstIndex(where: { $0.id == id }),
      peers[index].peripheralId != peripheralId
    else { return }
    peers[index].peripheralId = peripheralId
    persist()
  }

  func remove(id: UUID) {
    peers.removeAll { $0.id == id }
    persist()
  }

  private func persist() {
    storage.setPairingData(try? JSONEncoder().encode(peers), for: Self.peersKey)
  }
}
