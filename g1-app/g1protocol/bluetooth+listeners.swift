import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  func addOnConnectListener(listener: @escaping () -> Void) -> () -> Void {
    let result = onConnectListener.add(listener)
    if store.get(atom: isConnectedAtom) {
      onConnectListener.executeAll()
    }
    return result
  }
}
var onConnectListener = ClosureStore()

extension BluetoothManager {
  func onValue(peripheral: CBPeripheral, data: Data) {
    let side: Side = peripheral == leftPeripheral ? .left : .right
    guard let cmd = Cmd(rawValue: data[0]) else {
      handleUnknownCommands(peripheral: peripheral, data: data, side: side, store: store)
      return
    }
    if let listeners = listeners[cmd] {
      listeners.executeAll(peripheral: peripheral, data: data, side: side, store: store)
    } else {
      log("No listeners:", cmd, data)
    }
  }
}
let allListeners: [[Cmd: Listener]] = [infoListeners, configListeners, deviceListeners]

func addListener(key: Cmd, listener: @escaping Listener) -> () -> Void {
  if listeners[key] == nil {
    listeners[key] = ListenerClosureStore()
  }
  return listeners[key, default: ListenerClosureStore()].add(listener)
}

func addListeners() {
  for listeners in allListeners {
    for (key, value) in listeners {
      let _ = addListener(key: key, listener: value)
    }
  }
}

enum Side {
  case left
  case right
}
typealias Listener = (_ peripheral: CBPeripheral, _ data: Data, _ side: Side, _ store: JotaiStore)
  -> Void
var listeners: [Cmd: ListenerClosureStore] = [:]

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

class ClosureStore {
  typealias Closure = () -> Void
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

  func executeAll() {
    closureMap.values.forEach { $0() }
  }
}
