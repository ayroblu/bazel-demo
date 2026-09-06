import Foundation
import XCTest

@testable import connect

final class PairingStoreTests: XCTestCase {
  func testLocalIdIsStable() {
    let storage = MemoryPairingStorage()
    let first = PairingStore(storage: storage).localId
    XCTAssertEqual(PairingStore(storage: storage).localId, first)
  }

  func testPeersSurviveReload() {
    let storage = MemoryPairingStorage()
    let store = PairingStore(storage: storage)
    let peer = PairedPeer(
      id: UUID(), name: "Blu's iPhone", secret: ConnectCodec.newSecret(), peripheralId: nil)
    store.save(peer)

    let reloaded = PairingStore(storage: storage)
    XCTAssertEqual(reloaded.peers, [peer])
    XCTAssertEqual(reloaded.secret(for: peer.id), peer.secret)
  }

  func testNicknameWinsOverTheReportedName() {
    var peer = PairedPeer(id: UUID(), name: "iPhone", secret: Data([1]), peripheralId: nil)
    XCTAssertEqual(peer.displayName, "iPhone")

    peer.nickname = "Kitchen"
    XCTAssertEqual(peer.displayName, "Kitchen")

    // The device renaming itself must not take the user's name away.
    peer.name = "iPhone (2)"
    XCTAssertEqual(peer.displayName, "Kitchen")

    peer.nickname = nil
    XCTAssertEqual(peer.displayName, "iPhone (2)")
  }

  func testPeersPairedBeforeNicknamesStillLoad() {
    let storage = MemoryPairingStorage()
    let id = UUID()
    let stored = """
      [{"id":"\(id.uuidString)","name":"iPad","secret":"AQID"}]
      """
    storage.setPairingData(Data(stored.utf8), for: "connect.pairedPeers")

    let store = PairingStore(storage: storage)
    XCTAssertEqual(store.peers.count, 1)
    XCTAssertNil(store.peer(id: id)?.nickname)
    XCTAssertEqual(store.peer(id: id)?.displayName, "iPad")
  }

  func testSaveReplacesAndRemoveDeletes() {
    let store = PairingStore(storage: MemoryPairingStorage())
    var peer = PairedPeer(id: UUID(), name: "iPad", secret: Data([1]), peripheralId: nil)
    store.save(peer)
    peer.name = "Renamed"
    store.save(peer)
    XCTAssertEqual(store.peers.count, 1)
    XCTAssertEqual(store.peer(id: peer.id)?.name, "Renamed")

    store.remove(id: peer.id)
    XCTAssertTrue(store.peers.isEmpty)
  }

  func testPeripheralIdIsCachedAndSearchable() {
    let storage = MemoryPairingStorage()
    let store = PairingStore(storage: storage)
    let peer = PairedPeer(id: UUID(), name: "iPad", secret: Data([1]), peripheralId: nil)
    store.save(peer)

    let peripheralId = UUID()
    store.setPeripheralId(peripheralId, for: peer.id)
    XCTAssertEqual(store.peer(peripheralId: peripheralId)?.id, peer.id)
    XCTAssertEqual(PairingStore(storage: storage).peer(id: peer.id)?.peripheralId, peripheralId)
  }

  func testUnknownPeerHasNoSecret() {
    let store = PairingStore(storage: MemoryPairingStorage())
    XCTAssertNil(store.secret(for: UUID()))
    XCTAssertNil(store.peer(peripheralId: UUID()))
  }
}
