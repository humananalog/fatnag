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

/// Passive BLE scanner for Mi Body Composition Scale 2 advertisements.
///
/// XMTZC05HM / MIBFS broadcasts weight + impedance in service data `0x181B`.
/// No pairing or GATT connection is required for a live reading.
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
        // Keep scanning advertisements; connection is unnecessary for MIBFS broadcast frames.
        beginScanIfPossible()
    }

    private func beginScanIfPossible() {
        guard wantsScan else { return }
        guard central.state == .poweredOn else { return }
        // Do not filter by service UUID in the scan options: some iOS versions
        // only surface 0x181B inside the advertisement manufacturer/service-data
        // payload after an unfiltered scan.
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

        let looksLikeScale = MiScale2FrameDecoder.matchesAdvertisedName(name)
            || serviceData?.keys.contains(where: { $0.uuidString.uppercased().hasSuffix("181B") }) == true

        guard looksLikeScale else { return }

        knownPeripherals[peripheral.identifier] = peripheral
        let scale = DiscoveredScale(
            id: peripheral.identifier,
            name: name ?? "Mi Scale",
            rssi: rssi.intValue,
            lastSeen: Date()
        )
        delegate?.scaleScanner(self, didDiscover: scale)

        if let focused = focusedPeripheralID, focused != peripheral.identifier {
            return
        }

        guard let serviceData else { return }
        for (uuid, data) in serviceData {
            guard uuid.uuidString.uppercased().hasSuffix("181B") else { continue }
            switch MiScale2FrameDecoder.decode(data) {
            case .success(let measurement):
                if measurement.biaPending {
                    delegate?.scaleScanner(
                        self,
                        transientStatus: "Weight locked. Waiting for impedance sweep (stay barefoot)…"
                    )
                }
                delegate?.scaleScanner(self, didDecode: measurement)
            case .failure(.notStabilized):
                delegate?.scaleScanner(self, transientStatus: "Scale settling… keep standing still.")
            case .failure(.weightRemoved):
                delegate?.scaleScanner(self, transientStatus: "Weight removed. Step back on barefoot for body fat.")
            case .failure:
                break
            }
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
            delegate?.scaleScanner(self, didUpdateBluetoothState: "Bluetooth permission denied. Enable it for The Scale in Settings.")
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
