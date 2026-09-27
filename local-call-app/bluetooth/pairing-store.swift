import Foundation

/// `peripheralId` is cached so a paired peer shows as in range from a scan alone, without
/// connecting to read its identity.
public nonisolated struct PairedPeer: Codable, Equatable, Identifiable {
  public let id: UUID
  public var name: String
  public var nickname: String?
  var secret: Data
  public var peripheralId: UUID?

  public var displayName: String {
    guard let nickname, !nickname.isEmpty else { return name }
    return nickname
  }

  public init(id: UUID, name: String, nickname: String? = nil, secret: Data, peripheralId: UUID? = nil) {
    self.id = id
    self.name = name
    self.nickname = nickname
    self.secret = secret
    self.peripheralId = peripheralId
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

public nonisolated final class PairingStore {
  private let storage: PairingStorage
  private static let localIdKey = "connect.localId"
  private static let peersKey = "connect.pairedPeers"

  /// This device's stable identity in the signalling protocol. Bluetooth
  /// addresses rotate and peripheral handles differ per observer, so identity
  /// is carried in the messages instead.
  public let localId: UUID
  public private(set) var peers: [PairedPeer]

  public convenience init() {
    self.init(storage: UserDefaultsPairingStorage())
  }

  init(storage: PairingStorage) {
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

  public func peer(id: UUID) -> PairedPeer? {
    peers.first { $0.id == id }
  }

  func peer(peripheralId: UUID) -> PairedPeer? {
    peers.first { $0.peripheralId == peripheralId }
  }

  public func secret(for id: UUID) -> Data? {
    peer(id: id)?.secret
  }

  public func save(_ peer: PairedPeer) {
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

  public func remove(id: UUID) {
    peers.removeAll { $0.id == id }
    persist()
  }

  private func persist() {
    storage.setPairingData(try? JSONEncoder().encode(peers), for: Self.peersKey)
  }
}
