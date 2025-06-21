import CoreBluetooth
import Log
import jotai

extension BluetoothManager {
  func onValue(peripheral: CBPeripheral, data: Data) {
    guard let cmd = Cmd(rawValue: data[0]) else {
      log("unknown cmd", data[0])
      return
    }
    listeners[cmd]?.executeAll(peripheral: peripheral, data: data, side: .left, store: store)
  }

  func addOnConnectListener(listener: @escaping () -> Void) -> () -> Void {
    let result = onConnectListener.add(listener)
    if store.get(atom: isConnectedAtom) {
      onConnectListener.executeAll()
    }
    return result
  }
}

var onConnectListener = ClosureStore()

enum Side {
  case left
  case right
}
typealias Listener = (_ peripheral: CBPeripheral, _ data: Data, _ side: Side, _ store: JotaiStore)
  -> Void
var listeners = [
  Cmd: ListenerClosureStore
]()

func addListener(key: Cmd, listener: @escaping Listener) -> () -> Void {
  if listeners[key] == nil {
    listeners[key] = ListenerClosureStore()
  }
  return listeners[key, default: ListenerClosureStore()].add(listener)
}

func addListeners() {
  for listeners in [infoListeners] {
    for (key, value) in listeners {
      let _ = addListener(key: key, listener: value)
    }
  }
}

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
