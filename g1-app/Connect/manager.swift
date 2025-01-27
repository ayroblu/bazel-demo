import CoreBluetooth
import Log
import utils

struct ConnectionManager {
  let UARTServiceUUID = CBUUID(string: Constants.uartServiceUUIDString)
  let UARTTXCharacteristicUUID = CBUUID(string: Constants.uartTXCharacteristicUUIDString)
  let UARTRXCharacteristicUUID = CBUUID(string: Constants.uartRXCharacteristicUUIDString)
  let centralManager = CBCentralManager(delegate: BluetoothManager(), queue: nil)
}

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
}
