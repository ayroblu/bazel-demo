import CoreBluetooth
import Foundation
import Log

nonisolated(unsafe) let connectServiceUuid = CBUUID(string: "9C4B1E80-6F2D-4A6E-9B31-2D5A7C0E4F10")
nonisolated(unsafe) let connectSignalUuid = CBUUID(string: "9C4B1E81-6F2D-4A6E-9B31-2D5A7C0E4F10")
nonisolated(unsafe) let connectIdentityUuid = CBUUID(string: "9C4B1E82-6F2D-4A6E-9B31-2D5A7C0E4F10")

nonisolated final class Box<T>: @unchecked Sendable {
  let value: T
  init(_ value: T) {
    self.value = value
  }
}

public nonisolated struct NearbyPeer: Identifiable, Equatable {
  public let id: UUID
  public var name: String
  var peripheralId: UUID
}

/// The always-on half of the app. Every device publishes a small GATT service
/// and advertises it, which iOS keeps doing in the background, and a write to
/// its signal characteristic relaunches the app to ring. Scanning is the
/// expensive half and only runs in the foreground, which is where a caller is
/// by definition.
class NearbyLink: ObservableObject {
  private let store: PairingStore
  private let delegate = NearbyDelegate()
  private var central: CBCentralManager?
  private var server: CBPeripheralManager?
  private var signalCharacteristic: CBMutableCharacteristic?
  private var didAddService = false

  private var peripherals: [UUID: CBPeripheral] = [:]
  private var signalCharacteristics: [UUID: CBCharacteristic] = [:]
  private var identities: [UUID: NearbyPeer] = [:]
  private var lastSeen: [UUID: Date] = [:]
  private var centrals: [UUID: CBCentral] = [:]
  private var subscribedCentrals: Set<UUID> = []
  private var pendingWrites: [UUID: [Data]] = [:]
  private var pendingNotifies: [(peerId: UUID, data: Data)] = []
  private var heldPeers: Set<UUID> = []
  private var awaitingWrites: Set<UUID> = []
  private var resolveAttempts: [UUID: Date] = [:]
  private var pruneTask: Task<Void, Never>?

  @Published private(set) var nearby: [NearbyPeer] = []
  @Published private(set) var isScanning = false
  @Published private(set) var isPoweredOn = false

  var onMessage: ((ConnectFrame) -> Void)?
  var onNearbyChanged: (([NearbyPeer]) -> Void)?
  var localName: String

  init(store: PairingStore, localName: String) {
    self.store = store
    self.localName = ConnectCodec.trimmed(name: localName)
    delegate.link = self
  }

  /// Both managers are created with restore identifiers, which is what lets
  /// the system relaunch a terminated app into the background when a paired
  /// device writes to us.
  func start() {
    guard central == nil else { return }
    log("connect nearby start", store.localId.uuidString)
    server = CBPeripheralManager(
      delegate: delegate, queue: nil,
      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "connect.peripheral"])
    central = CBCentralManager(
      delegate: delegate, queue: nil,
      options: [CBCentralManagerOptionRestoreIdentifierKey: "connect.central"])
  }

  func setScanning(_ scanning: Bool) {
    guard scanning != isScanning else { return }
    isScanning = scanning
    if scanning {
      startScanIfPossible()
      startPruning()
    } else {
      central?.stopScan()
      pruneTask?.cancel()
      pruneTask = nil
      lastSeen = [:]
      refreshNearby()
      disconnectIdle()
    }
    log("connect scanning", scanning)
  }

  /// Keeps the bluetooth connection to a peer alive for the length of a call,
  /// so its answer, decline and hangup can come back as notifications.
  func hold(peerId: UUID) {
    heldPeers.insert(peerId)
    connectIfNeeded(peerId: peerId)
  }

  func release(peerId: UUID) {
    heldPeers.remove(peerId)
    disconnectIdle()
  }

  func send(_ message: ConnectMessage, to peerId: UUID) {
    let secret = message.isPairing ? nil : store.secret(for: peerId)
    if !message.isPairing && secret == nil {
      log("connect send to unpaired peer ignored", peerId.uuidString)
      return
    }
    let data = ConnectCodec.seal(message, senderId: store.localId, secret: secret)
    log("connect send", String(describing: message), "to", peerId.uuidString, data.count)
    if writeToPeripheral(data, peerId: peerId) { return }
    // A notification is unacknowledged and is silently dropped once the
    // central has gone, so it is only used for a peer this device cannot
    // reach as a central itself.
    if peripheralId(for: peerId) == nil, notifyCentral(data, peerId: peerId) { return }
    log("connect queued frame", peerId.uuidString)
    pendingWrites[peerId, default: []].append(data)
    connectIfNeeded(peerId: peerId)
  }

  func peripheralId(for peerId: UUID) -> UUID? {
    store.peer(id: peerId)?.peripheralId
      ?? identities.first { $0.value.id == peerId }?.key
  }

  /// Identities resolved by reading a peripheral only live for the session,
  /// so a paired peer is looked up in the store as well.
  private func peerId(forPeripheral peripheralId: UUID) -> UUID? {
    identities[peripheralId]?.id ?? store.peer(peripheralId: peripheralId)?.id
  }

  private func writeToPeripheral(_ data: Data, peerId: UUID) -> Bool {
    guard let peripheralId = peripheralId(for: peerId),
      let peripheral = peripherals[peripheralId], peripheral.state == .connected,
      let characteristic = signalCharacteristics[peripheralId]
    else { return false }
    awaitingWrites.insert(peripheralId)
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
    return true
  }

  /// `updateValue` reports success for a central that has gone away, so a
  /// notification is only a delivery path while that central is subscribed.
  private func notifyCentral(_ data: Data, peerId: UUID) -> Bool {
    guard let central = centrals[peerId], subscribedCentrals.contains(central.identifier),
      let characteristic = signalCharacteristic, let server
    else { return false }
    if server.updateValue(data, for: characteristic, onSubscribedCentrals: [central]) {
      return true
    }
    pendingNotifies.append((peerId, data))
    return true
  }

  private func connectIfNeeded(peerId: UUID) {
    guard let peripheralId = peripheralId(for: peerId), let central else { return }
    let peripheral =
      peripherals[peripheralId]
      ?? central.retrievePeripherals(withIdentifiers: [peripheralId]).first
    guard let peripheral else {
      log("connect no peripheral handle for peer", peerId.uuidString)
      return
    }
    peripherals[peripheralId] = peripheral
    peripheral.delegate = delegate
    log("connect connecting", peripheralId.uuidString, peripheral.state.rawValue)
    guard peripheral.state != .connected else {
      // Connected without a usable characteristic means an earlier discovery
      // never finished, and nothing else would retry it.
      if signalCharacteristics[peripheralId] == nil {
        peripheral.discoverServices([connectServiceUuid])
      }
      return
    }
    guard peripheral.state != .connecting else { return }
    central.connect(peripheral)
  }

  private func startScanIfPossible() {
    guard isScanning, let central, central.state == .poweredOn else { return }
    central.scanForPeripherals(
      withServices: [connectServiceUuid],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
  }

  /// Advertisements from a backgrounded peer carry no name and no service
  /// data, so a peer that has never been identified has to be connected to
  /// once to read who it is. The mapping is cached, and persisted for peers
  /// that end up paired.
  private func startPruning() {
    pruneTask?.cancel()
    pruneTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard let self, self.isScanning else { return }
        let cutoff = Date().addingTimeInterval(-12)
        self.lastSeen = self.lastSeen.filter { $0.value > cutoff }
        self.refreshNearby()
      }
    }
  }

  private func refreshNearby() {
    let seen = Set(lastSeen.keys)
    let updated =
      identities
      .filter { seen.contains($0.key) }
      .values
      .sorted { $0.name < $1.name }
    guard updated != nearby else { return }
    nearby = updated
    onNearbyChanged?(updated)
  }

  /// Nothing stays connected for longer than it needs to: identity is read
  /// once, and only a call or a pairing in flight keeps a link open.
  private func disconnectIdle() {
    guard let central else { return }
    for (peripheralId, peripheral) in peripherals {
      let peerId = peerId(forPeripheral: peripheralId)
      let isHeld = peerId.map { heldPeers.contains($0) } ?? false
      let hasPending = peerId.map { pendingWrites[$0]?.isEmpty == false } ?? false
      guard !isHeld, !hasPending, !awaitingWrites.contains(peripheralId),
        peripheral.state != .disconnected
      else { continue }
      central.cancelPeripheralConnection(peripheral)
    }
  }

  func handleWriteComplete(_ peripheral: CBPeripheral) {
    awaitingWrites.remove(peripheral.identifier)
    disconnectIdle()
  }

  private func flushPendingWrites(peerId: UUID) {
    guard let queued = pendingWrites[peerId], !queued.isEmpty else { return }
    pendingWrites[peerId] = []
    for data in queued where !writeToPeripheral(data, peerId: peerId) {
      log("connect dropped queued frame", peerId.uuidString)
    }
  }

  private var identityPayload: Data {
    var data = Data(withUnsafeBytes(of: store.localId.uuid) { Array($0) })
    data.append(Data(localName.utf8))
    return data
  }

  private func identity(from data: Data, peripheralId: UUID) -> NearbyPeer? {
    let raw = [UInt8](data)
    guard raw.count > 16 else { return nil }
    let idBytes = Array(raw[0..<16])
    let id = UUID(
      uuid: (
        idBytes[0], idBytes[1], idBytes[2], idBytes[3], idBytes[4], idBytes[5], idBytes[6],
        idBytes[7], idBytes[8], idBytes[9], idBytes[10], idBytes[11], idBytes[12], idBytes[13],
        idBytes[14], idBytes[15]
      ))
    let name = String(decoding: raw[16...], as: UTF8.self)
    return NearbyPeer(id: id, name: name, peripheralId: peripheralId)
  }

  func handleCentralState(_ state: CBManagerState) {
    log("connect central state", state.rawValue)
    isPoweredOn = state == .poweredOn
    guard state == .poweredOn else { return }
    startScanIfPossible()
    for peerId in heldPeers {
      connectIfNeeded(peerId: peerId)
    }
  }

  func handleServerState(_ state: CBManagerState) {
    log("connect server state", state.rawValue)
    guard state == .poweredOn, let server else { return }
    guard !didAddService else {
      startAdvertising()
      return
    }
    let signal = CBMutableCharacteristic(
      type: connectSignalUuid, properties: [.write, .notify], value: nil,
      permissions: [.writeable])
    let identity = CBMutableCharacteristic(
      type: connectIdentityUuid, properties: [.read], value: nil, permissions: [.readable])
    let service = CBMutableService(type: connectServiceUuid, primary: true)
    service.characteristics = [signal, identity]
    signalCharacteristic = signal
    didAddService = true
    server.removeAllServices()
    server.add(service)
  }

  func handleServiceAdded(error: Error?) {
    if let error {
      log("connect failed to publish service", error)
      didAddService = false
      return
    }
    startAdvertising()
  }

  private func startAdvertising() {
    guard let server, !server.isAdvertising else { return }
    server.startAdvertising([
      CBAdvertisementDataServiceUUIDsKey: [connectServiceUuid],
      CBAdvertisementDataLocalNameKey: localName,
    ])
  }

  func handleRestoredServices(_ services: [CBMutableService]) {
    guard
      let service = services.first(where: { $0.uuid == connectServiceUuid }),
      let signal = service.characteristics?.first(where: { $0.uuid == connectSignalUuid })
        as? CBMutableCharacteristic
    else { return }
    log("connect restored service")
    signalCharacteristic = signal
    didAddService = true
  }

  func handleRestoredPeripherals(_ restored: [CBPeripheral]) {
    for peripheral in restored {
      peripherals[peripheral.identifier] = peripheral
      peripheral.delegate = delegate
    }
  }

  func handleDiscovered(_ peripheral: CBPeripheral, name: String?) {
    peripherals[peripheral.identifier] = peripheral
    peripheral.delegate = delegate
    let isNew = lastSeen[peripheral.identifier] == nil
    lastSeen[peripheral.identifier] = Date()
    if identities[peripheral.identifier] == nil,
      let paired = store.peer(peripheralId: peripheral.identifier)
    {
      identities[peripheral.identifier] = NearbyPeer(
        id: paired.id, name: paired.name, peripheralId: peripheral.identifier)
    }
    if identities[peripheral.identifier] == nil {
      if isNew {
        log("connect resolving identity", peripheral.identifier.uuidString, name ?? "-")
      }
      connectForIdentity(peripheral)
    }
    refreshNearby()
  }

  private func connectForIdentity(_ peripheral: CBPeripheral) {
    guard peripheral.state == .disconnected, let central else { return }
    let now = Date()
    if let attempt = resolveAttempts[peripheral.identifier], now.timeIntervalSince(attempt) < 10 {
      return
    }
    resolveAttempts[peripheral.identifier] = now
    central.connect(peripheral)
  }

  func handleConnected(_ peripheral: CBPeripheral) {
    log("connect peripheral connected", peripheral.identifier.uuidString)
    peripheral.delegate = delegate
    peripheral.discoverServices([connectServiceUuid])
  }

  func handleDisconnected(_ peripheral: CBPeripheral) {
    log("connect peripheral disconnected", peripheral.identifier.uuidString)
    signalCharacteristics[peripheral.identifier] = nil
    awaitingWrites.remove(peripheral.identifier)
    guard let peerId = peerId(forPeripheral: peripheral.identifier),
      heldPeers.contains(peerId) || pendingWrites[peerId]?.isEmpty == false
    else { return }
    central?.connect(peripheral)
  }

  func handleDiscoveredCharacteristics(_ peripheral: CBPeripheral, _ service: CBService) {
    for characteristic in service.characteristics ?? [] {
      switch characteristic.uuid {
      case connectSignalUuid:
        signalCharacteristics[peripheral.identifier] = characteristic
        peripheral.setNotifyValue(true, for: characteristic)
        if let peerId = peerId(forPeripheral: peripheral.identifier) {
          flushPendingWrites(peerId: peerId)
        }
      case connectIdentityUuid:
        peripheral.readValue(for: characteristic)
      default:
        break
      }
    }
  }

  func handleValue(_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
    guard let data = characteristic.value else { return }
    switch characteristic.uuid {
    case connectIdentityUuid:
      guard let peer = identity(from: data, peripheralId: peripheral.identifier) else { return }
      log("connect identified", peer.name, peer.id.uuidString)
      identities[peripheral.identifier] = peer
      resolveAttempts[peripheral.identifier] = nil
      if store.peer(id: peer.id) != nil {
        store.setPeripheralId(peripheral.identifier, for: peer.id)
      }
      refreshNearby()
      flushPendingWrites(peerId: peer.id)
      disconnectIdle()
    case connectSignalUuid:
      deliver(data)
    default:
      break
    }
  }

  func handleWrite(_ data: Data, from central: CBCentral) {
    guard let frame = deliver(data) else { return }
    centrals[frame.senderId] = central
  }

  @discardableResult
  private func deliver(_ data: Data) -> ConnectFrame? {
    do {
      let frame = try ConnectCodec.open(data) { [weak self] senderId in
        self?.store.secret(for: senderId)
      }
      log("connect received", String(describing: frame.message), frame.senderId.uuidString)
      onMessage?(frame)
      return frame
    } catch {
      log("connect rejected frame", data.count, String(describing: error))
      return nil
    }
  }

  func handleReadRequest(_ request: CBATTRequest) {
    guard request.characteristic.uuid == connectIdentityUuid else {
      server?.respond(to: request, withResult: .requestNotSupported)
      return
    }
    let payload = identityPayload
    guard request.offset <= payload.count else {
      server?.respond(to: request, withResult: .invalidOffset)
      return
    }
    request.value = payload.subdata(in: request.offset..<payload.count)
    server?.respond(to: request, withResult: .success)
  }

  func handleReadyToNotify() {
    let queued = pendingNotifies
    pendingNotifies = []
    for item in queued {
      _ = notifyCentral(item.data, peerId: item.peerId)
    }
  }

  func handleSubscribe(_ central: CBCentral) {
    subscribedCentrals.insert(central.identifier)
  }

  func handleUnsubscribe(_ central: CBCentral) {
    subscribedCentrals.remove(central.identifier)
    centrals = centrals.filter { $0.value.identifier != central.identifier }
  }
}

/// CoreBluetooth's delegates are not main actor isolated, so every callback
/// hops onto the main actor the way the transport's callbacks do.
nonisolated final class NearbyDelegate: NSObject, CBCentralManagerDelegate,
  CBPeripheralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable
{
  weak var link: NearbyLink?

  private func onMain(_ body: @escaping @MainActor (NearbyLink) -> Void) {
    Task { @MainActor [weak link] in
      guard let link else { return }
      body(link)
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let state = central.state
    onMain { $0.handleCentralState(state) }
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let restored = Box((dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? [])
    onMain { $0.handleRestoredPeripherals(restored.value) }
  }

  func centralManager(
    _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber
  ) {
    let box = Box(peripheral)
    let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    onMain { $0.handleDiscovered(box.value, name: name) }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    let box = Box(peripheral)
    onMain { $0.handleConnected(box.value) }
  }

  func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    log("connect failed to connect", peripheral.identifier.uuidString, String(describing: error))
    let box = Box(peripheral)
    onMain { $0.handleDisconnected(box.value) }
  }

  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
  ) {
    let box = Box(peripheral)
    onMain { $0.handleDisconnected(box.value) }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let service = peripheral.services?.first(where: { $0.uuid == connectServiceUuid }) else {
      log("connect service missing", peripheral.identifier.uuidString, String(describing: error))
      return
    }
    peripheral.discoverCharacteristics([connectSignalUuid, connectIdentityUuid], for: service)
  }

  func peripheral(
    _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
  ) {
    let peripheralBox = Box(peripheral)
    let serviceBox = Box(service)
    onMain { $0.handleDiscoveredCharacteristics(peripheralBox.value, serviceBox.value) }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if let error {
      log("connect read failed", characteristic.uuid.uuidString, error)
      return
    }
    let peripheralBox = Box(peripheral)
    let characteristicBox = Box(characteristic)
    onMain { $0.handleValue(peripheralBox.value, characteristicBox.value) }
  }

  func peripheral(
    _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
  ) {
    if let error {
      log("connect write failed", peripheral.identifier.uuidString, error)
    }
    let box = Box(peripheral)
    onMain { $0.handleWriteComplete(box.value) }
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    let state = peripheral.state
    onMain { $0.handleServerState(state) }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
    let services = Box((dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService]) ?? [])
    onMain { $0.handleRestoredServices(services.value) }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?
  ) {
    let box = Box(error)
    onMain { $0.handleServiceAdded(error: box.value) }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]
  ) {
    guard let first = requests.first else { return }
    peripheral.respond(to: first, withResult: .success)
    for request in requests {
      guard request.characteristic.uuid == connectSignalUuid, let data = request.value else {
        continue
      }
      let dataBox = Box(data)
      let centralBox = Box(request.central)
      onMain { $0.handleWrite(dataBox.value, from: centralBox.value) }
    }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest
  ) {
    let box = Box(request)
    onMain { $0.handleReadRequest(box.value) }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    onMain { $0.handleReadyToNotify() }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didSubscribeTo characteristic: CBCharacteristic
  ) {
    let box = Box(central)
    onMain { $0.handleSubscribe(box.value) }
  }

  func peripheralManager(
    _ peripheral: CBPeripheralManager, central: CBCentral,
    didUnsubscribeFrom characteristic: CBCharacteristic
  ) {
    let box = Box(central)
    onMain { $0.handleUnsubscribe(box.value) }
  }
}
