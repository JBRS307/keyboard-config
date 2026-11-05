// Reads every Battery Level value from connected Bluetooth LE devices.
// With ZMK's battery proxy enabled, a split keyboard reports one value per half.
// Run: swift zmk-battery.swift

import CoreBluetooth
import Foundation

let batteryService = CBUUID(string: "180F")
let batteryLevel   = CBUUID(string: "2A19")
let userDesc       = CBUUID(string: "2901")

final class Reader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var peripherals: [CBPeripheral] = []
    // Per characteristic: device name, label (from descriptor, if any), level
    var entries: [ObjectIdentifier: (device: String, label: String?, level: Int?)] = [:]
    var order: [ObjectIdentifier] = []

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: break
        case .unauthorized:
            print("Bluetooth access denied. Allow your terminal app in System Settings > Privacy & Security > Bluetooth.")
            exit(1)
        case .unknown, .resetting: return
        default:
            print("Bluetooth is not available."); exit(1)
        }
        peripherals = c.retrieveConnectedPeripherals(withServices: [batteryService])
        if peripherals.isEmpty {
            print("No connected Bluetooth devices report a battery level."); exit(0)
        }
        for p in peripherals { p.delegate = self; c.connect(p) }
        // Print whatever was collected after a few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.report() }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([batteryService])
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([batteryLevel], for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where ch.uuid == batteryLevel {
            let id = ObjectIdentifier(ch)
            if entries[id] == nil {
                entries[id] = (p.name ?? "Unknown device", nil, nil)
                order.append(id)
            }
            p.readValue(for: ch)
            p.discoverDescriptors(for: ch)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let byte = ch.value?.first else { return }
        entries[ObjectIdentifier(ch)]?.level = Int(byte)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor ch: CBCharacteristic, error: Error?) {
        for d in ch.descriptors ?? [] where d.uuid == userDesc { p.readValue(for: d) }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor d: CBDescriptor, error: Error?) {
        guard let ch = d.characteristic, let text = d.value as? String else { return }
        entries[ObjectIdentifier(ch)]?.label = text
    }

    func report() {
        var counter: [String: Int] = [:]
        for id in order {
            guard let e = entries[id] else { continue }
            counter[e.device, default: 0] += 1
            // ZMK labels the peripheral's value (e.g. "Peripheral 0"); the unlabeled one is the central half.
            let label = e.label ?? (counter[e.device] == 1 ? "Central" : "Battery \(counter[e.device]!)")
            let level = e.level.map { "\($0)%" } ?? "no reading"
            print("\(e.device) — \(label): \(level)")
        }
        exit(0)
    }
}

let reader = Reader()
RunLoop.main.run()
