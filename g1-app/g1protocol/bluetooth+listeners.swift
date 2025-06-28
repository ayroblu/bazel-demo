import CoreBluetooth
import Log
import jotai
import utils

extension BluetoothManager {
  public func addOnConnectListener(_ listener: @escaping (String, String) -> Void) -> () -> Void {
    let unsub = onConnectListener.sub(listener)
    if manager.store.get(atom: isConnectedAtom) {
      guard let left = manager.leftPeripheral, let right = manager.rightPeripheral else {
        return unsub
      }
      onConnectListener.dispatch { f in
        f(left.identifier.uuidString, right.identifier.uuidString)
      }
    }
    return unsub
  }
}
var onConnectListener = SubscriptionSet<(String, String) -> Void>()

extension G1BluetoothManager {
  func onValue(peripheral: CBPeripheral, data: Data) {
    let side: Side = peripheral == leftPeripheral ? .left : .right
    guard let cmd = Cmd(rawValue: data[0]) else {
      handleUnknownCommands(peripheral: peripheral, data: data, side: side, store: store)
      return
    }
    if let listeners = listeners[cmd] {
      listeners.dispatch { f in
        f(peripheral, data, side, store)
      }
    } else {
      log("No listeners:", cmd, data.hex)
    }
  }
}
let allListeners: [[Cmd: Listener]] = [infoListeners, configListeners, deviceListeners]
var isFirst = true
var listeners: [Cmd: SubscriptionSet<(CBPeripheral, Data, Side, JotaiStore) -> Void>] {
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
    _listeners[key] = SubscriptionSet()
  }
  return _listeners[key, default: SubscriptionSet()].sub(listener)
}

public enum Side {
  case left
  case right
}
public typealias Listener = (
  _ peripheral: CBPeripheral, _ data: Data, _ side: Side, _ store: JotaiStore
)
  -> Void
var _listeners: [Cmd: SubscriptionSet<(CBPeripheral, Data, Side, JotaiStore) -> Void>] = [:]
