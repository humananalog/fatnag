import CoreBluetooth
import Foundation

protocol ScaleScanning: AnyObject {
    var delegate: ScaleScannerDelegate? { get set }
    func startScanning()
    func stop()
    func focus(on peripheralID: UUID)
}

protocol ScaleScannerDelegate: AnyObject {
    func scaleScanner(_ scanner: ScaleScanning, didUpdateBluetoothState message: String?)
    func scaleScanner(_ scanner: ScaleScanning, didDiscover scale: DiscoveredScale)
    func scaleScanner(_ scanner: ScaleScanning, didDecode measurement: ScaleMeasurement)
    func scaleScanner(_ scanner: ScaleScanning, transientStatus: String)
}

/// Passive BLE scanner for compatible body-scale advertisements.
///
/// Scans unfiltered, then matches ads through `ScaleFrameDecoderRegistry`
/// (Mi Body Composition Scale 2 today; other brands/models can register next).
/// No pairing or GATT connection is required for broadcast readings.
final class CoreBluetoothScaleScanner: NSObject, ScaleScanning {
    weak var delegate: ScaleScannerDelegate?

    private var central: CBCentralManager!
    private var focusedPeripheralID: UUID?
    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var wantsScan = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    func startScanning() {
        wantsScan = true
        focusedPeripheralID = nil
        beginScanIfPossible()
    }

    func stop() {
        wantsScan = false
        focusedPeripheralID = nil
        if central.state == .poweredOn {
            central.stopScan()
        }
    }

    func focus(on peripheralID: UUID) {
        focusedPeripheralID = peripheralID
        // Keep scanning advertisements; connection is unnecessary for broadcast frames.
        beginScanIfPossible()
    }

    private func beginScanIfPossible() {
        guard wantsScan else { return }
        guard central.state == .poweredOn else { return }
        // Do not filter by service UUID in the scan options: some iOS versions
        // only surface scale service-data after an unfiltered scan.
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    private func handleAdvertisement(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]

        guard let decoder = ScaleFrameDecoderRegistry.matching(
            advertisedName: name,
            serviceData: serviceData
        ) else { return }

        knownPeripherals[peripheral.identifier] = peripheral
        let scale = DiscoveredScale(
            id: peripheral.identifier,
            name: name ?? decoder.fallbackAdvertisedName,
            rssi: rssi.intValue,
            lastSeen: Date()
        )
        delegate?.scaleScanner(self, didDiscover: scale)

        if let focused = focusedPeripheralID, focused != peripheral.identifier {
            return
        }

        guard let serviceData else { return }
        switch ScaleFrameDecoderRegistry.decodeLive(serviceData: serviceData) {
        case .measurement(let measurement, _):
            if !measurement.isStabilized {
                delegate?.scaleScanner(self, transientStatus: "Live weight… keep standing still.")
            } else if measurement.biaPending {
                delegate?.scaleScanner(
                    self,
                    transientStatus: "Weight locked. Waiting for body composition (stay barefoot)…"
                )
            }
            delegate?.scaleScanner(self, didDecode: measurement)
        case .weightRemoved:
            delegate?.scaleScanner(self, transientStatus: "Weight removed. Step back on barefoot for body fat.")
        case .none:
            break
        }
    }
}

extension CoreBluetoothScaleScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            delegate?.scaleScanner(self, didUpdateBluetoothState: nil)
            beginScanIfPossible()
        case .poweredOff:
            delegate?.scaleScanner(self, didUpdateBluetoothState: "Bluetooth is off. Turn it on in Settings.")
        case .unauthorized:
            delegate?.scaleScanner(self, didUpdateBluetoothState: "Bluetooth permission denied. Enable it for FATNAG in Settings.")
        case .unsupported:
            delegate?.scaleScanner(self, didUpdateBluetoothState: "This device does not support Bluetooth LE.")
        case .resetting:
            delegate?.scaleScanner(self, didUpdateBluetoothState: "Bluetooth is resetting…")
        case .unknown:
            delegate?.scaleScanner(self, didUpdateBluetoothState: "Waiting for Bluetooth…")
        @unknown default:
            delegate?.scaleScanner(self, didUpdateBluetoothState: "Bluetooth unavailable.")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        handleAdvertisement(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
}
