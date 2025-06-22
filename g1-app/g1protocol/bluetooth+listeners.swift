import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  public func addOnConnectListener(_ listener: @escaping (String, String) -> Void) -> () -> Void {
    let result = onConnectListener.add(listener)
    if manager.store.get(atom: isConnectedAtom) {
      guard let left = manager.leftPeripheral, let right = manager.rightPeripheral else {
        return result
      }
      onConnectListener.executeAll(
        left.identifier.uuidString, right.identifier.uuidString)
    }
    return result
  }
}
var onConnectListener = OnConnectClosureStore()

extension G1BluetoothManager {
  func onValue(peripheral: CBPeripheral, data: Data) {
    let side: Side = peripheral == leftPeripheral ? .left : .right
    guard let cmd = Cmd(rawValue: data[0]) else {
      handleUnknownCommands(peripheral: peripheral, data: data, side: side, store: store)
      return
    }
    if let listeners = listeners[cmd] {
      listeners.executeAll(peripheral: peripheral, data: data, side: side, store: store)
    } else {
      log("No listeners:", cmd, data.hex)
    }
  }
}
let allListeners: [[Cmd: Listener]] = [infoListeners, configListeners, deviceListeners]
var isFirst = true
var listeners: [Cmd: ListenerClosureStore] {
  if isFirst {
    isFirst = false
    for l in allListeners {
      for (key, value) in l {
        let _ = addListener(key: key, listener: value)
      }
    }
  }
  return _listeners
}

public func addListener(key: Cmd, listener: @escaping Listener) -> () -> Void {
  if _listeners[key] == nil {
    _listeners[key] = ListenerClosureStore()
  }
  return _listeners[key, default: ListenerClosureStore()].add(listener)
}

public enum Side {
  case left
  case right
}
public typealias Listener = (
  _ peripheral: CBPeripheral, _ data: Data, _ side: Side, _ store: JotaiStore
)
  -> Void
var _listeners: [Cmd: ListenerClosureStore] = [:]

class ListenerClosureStore {
  private var closures: Set<UUID> = []
  private var closureMap: [UUID: Listener] = [:]

  func add(_ closure: @escaping Listener) -> () -> Void {
    let id = UUID()
    closures.insert(id)
    closureMap[id] = closure

    return { [weak self] in
      self?.closures.remove(id)
      self?.closureMap.removeValue(forKey: id)
    }
  }

  func executeAll(peripheral: CBPeripheral, data: Data, side: Side, store: JotaiStore) {
    closureMap.values.forEach { $0(peripheral, data, side, store) }
  }
}

class OnConnectClosureStore {
  typealias Closure = (String, String) -> Void
  private var closures: Set<UUID> = []
  private var closureMap: [UUID: Closure] = [:]

  func add(_ closure: @escaping Closure) -> () -> Void {
    let id = UUID()
    closures.insert(id)
    closureMap[id] = closure

    return { [weak self] in
      self?.closures.remove(id)
      self?.closureMap.removeValue(forKey: id)
    }
  }

  func executeAll(_ left: String, _ right: String) {
    closureMap.values.forEach { $0(left, right) }
  }
}
