import CoreBluetooth
import SwiftUI
import WebKit

// The native half of Web Bluetooth (bridge.js is the web half). Each call from the
// page arrives as {id, op, args}; the answer goes back with window.__tbBle.done(id, ok,
// value). Notifications and disconnects are pushed with __tbBle.value / __tbBle.dropped.
// Devices are identified by their CoreBluetooth UUID, services as "<device>|<service>",
// characteristics as "<device>|<service>|<characteristic>".

struct PickRequest: Identifiable {
    let id: Int
    let filters: [[String: Any]]
    let all: Bool
}

struct FoundDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
}

final class BLEBridge: NSObject, ObservableObject, WKScriptMessageHandler, CBCentralManagerDelegate, CBPeripheralDelegate {
    weak var webView: WKWebView?
    @Published var picker: PickRequest?
    @Published var found: [FoundDevice] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var waitingForPower: [() -> Void] = []
    // Calls waiting on CoreBluetooth, by what they wait for.
    private var connectWaits: [UUID: [Int]] = [:]
    private var serviceWaits: [UUID: [(Int, String)]] = [:]
    private var charWaits: [String: [(Int, String)]] = [:]
    private var notifyWaits: [String: [Int]] = [:]
    private var writeWaits: [String: [Int]] = [:]
    private var readWaits: [String: [Int]] = [:]
    // Devices you picked before, so the picker can take them straight away next time.
    private let knownKey = "tb.knownDevices"

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var anyConnected: Bool { peripherals.values.contains { $0.state == .connected } }

    // MARK: messages from the page

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = body["id"] as? Int, let op = body["op"] as? String else { return }
        let a = body["args"] as? [String: Any] ?? [:]
        whenPoweredOn(id) { [weak self] in self?.handle(id, op, a) }
    }

    private func handle(_ id: Int, _ op: String, _ a: [String: Any]) {
        switch op {
        case "request":
            found = []
            picker = PickRequest(id: id, filters: a["filters"] as? [[String: Any]] ?? [], all: a["all"] as? Bool ?? false)
            for p in central.retrieveConnectedPeripherals(withServices: wantedServices()) { consider(p, rssi: 0, adv: [:]) }
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case "connect":
            guard let p = device(a["d"]) else { return fail(id, "Unknown device") }
            if p.state == .connected { return ok(id) }
            connectWaits[p.identifier, default: []].append(id)
            central.connect(p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, let w = self.connectWaits[p.identifier], w.contains(id) else { return }
                self.connectWaits[p.identifier] = w.filter { $0 != id }
                self.central.cancelPeripheralConnection(p)
                self.fail(id, "Connection timed out")
            }
        case "disconnect":
            if let p = device(a["d"]) { central.cancelPeripheralConnection(p) }
            ok(id)
        case "service":
            guard let p = device(a["d"]), let u = a["u"] as? String else { return fail(id, "Unknown device") }
            guard p.state == .connected else { return fail(id, "GATT Server is disconnected.") }
            if p.services?.contains(where: { same($0.uuid, u) }) == true { return ok(id, ["id": "\(p.identifier.uuidString)|\(u)"]) }
            serviceWaits[p.identifier, default: []].append((id, u))
            p.discoverServices([cb(u)])
        case "char":
            guard let s = a["s"] as? String, let u = a["u"] as? String, let (p, svc) = service(s) else { return fail(id, "Unknown service") }
            if svc.characteristics?.contains(where: { same($0.uuid, u) }) == true { return ok(id, ["id": "\(s)|\(u)"]) }
            charWaits[s, default: []].append((id, u))
            p.discoverCharacteristics([cb(u)], for: svc)
        case "notify":
            guard let c = a["c"] as? String, let (p, ch) = characteristic(c) else { return fail(id, "Unknown characteristic") }
            notifyWaits[c, default: []].append(id)
            p.setNotifyValue(a["on"] as? Bool ?? true, for: ch)
        case "read":
            guard let c = a["c"] as? String, let (p, ch) = characteristic(c) else { return fail(id, "Unknown characteristic") }
            readWaits[c, default: []].append(id)
            p.readValue(for: ch)
        case "write":
            guard let c = a["c"] as? String, let (p, ch) = characteristic(c),
                  let data = Data(base64Encoded: a["b"] as? String ?? "") else { return fail(id, "Unknown characteristic") }
            let resp = a["resp"] as? Bool ?? true
            if !resp && ch.properties.contains(.writeWithoutResponse) {
                p.writeValue(data, for: ch, type: .withoutResponse)
                ok(id)
            } else {
                writeWaits[c, default: []].append(id)
                p.writeValue(data, for: ch, type: .withResponse)
            }
        default:
            fail(id, "Not supported: \(op)")
        }
    }

    // MARK: the device picker

    func choose(_ uuid: UUID) {
        guard let req = picker, let p = peripherals[uuid] else { return }
        central.stopScan()
        picker = nil
        var known = UserDefaults.standard.stringArray(forKey: knownKey) ?? []
        if !known.contains(uuid.uuidString) { known.append(uuid.uuidString); UserDefaults.standard.set(known, forKey: knownKey) }
        ok(req.id, ["id": uuid.uuidString, "name": p.name ?? "Device"])
    }

    func cancelPick() {
        guard let req = picker else { return }
        central.stopScan()
        picker = nil
        fail(req.id, "User cancelled the requestDevice() chooser.")
    }

    private func wantedServices() -> [CBUUID] {
        (picker?.filters ?? []).flatMap { ($0["services"] as? [String] ?? []).map(cb) }
    }

    private func matches(_ p: CBPeripheral, _ adv: [String: Any]) -> Bool {
        guard let req = picker else { return false }
        let name = p.name ?? adv[CBAdvertisementDataLocalNameKey] as? String ?? ""
        if req.all { return !name.isEmpty }
        let advertised = (adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []) + (p.services?.map(\.uuid) ?? [])
        for f in req.filters {
            let services = f["services"] as? [String] ?? []
            let exact = f["name"] as? String, prefix = f["namePrefix"] as? String
            var hit = true
            if !services.isEmpty { hit = hit && services.allSatisfy { s in advertised.contains { same($0, s) } } }
            if let exact { hit = hit && name == exact }
            if let prefix { hit = hit && name.hasPrefix(prefix) }
            if services.isEmpty && exact == nil && prefix == nil { hit = false }
            if hit { return true }
        }
        return false
    }

    private func consider(_ p: CBPeripheral, rssi: Int, adv: [String: Any]) {
        guard picker != nil, matches(p, adv) else { return }
        peripherals[p.identifier] = p
        p.delegate = self
        let name = p.name ?? adv[CBAdvertisementDataLocalNameKey] as? String ?? "Device"
        if let i = found.firstIndex(where: { $0.id == p.identifier }) { found[i].rssi = rssi; found[i].name = name }
        else { found.append(FoundDevice(id: p.identifier, name: name, rssi: rssi)) }
        // A device you picked before: take it, no list to tap through.
        if let req = picker, !req.all,
           (UserDefaults.standard.stringArray(forKey: knownKey) ?? []).contains(p.identifier.uuidString) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.picker?.id == req.id { self?.choose(p.identifier) }
            }
        }
    }

    // MARK: CoreBluetooth

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            let w = waitingForPower; waitingForPower = []
            w.forEach { $0() }
        }
    }

    private func whenPoweredOn(_ id: Int, _ run: @escaping () -> Void) {
        switch central.state {
        case .poweredOn: run()
        case .unauthorized: fail(id, "Bluetooth permission is off — allow it in Settings → Training Brain")
        case .poweredOff: fail(id, "Bluetooth is off — turn it on in Control Centre")
        case .unsupported: fail(id, "This iPhone has no Bluetooth LE")
        default: waitingForPower.append(run)
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData adv: [String: Any], rssi: NSNumber) {
        consider(p, rssi: rssi.intValue, adv: adv)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self
        (connectWaits.removeValue(forKey: p.identifier) ?? []).forEach { ok($0) }
        UIApplication.shared.isIdleTimerDisabled = true // keep the screen on while riding
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        (connectWaits.removeValue(forKey: p.identifier) ?? []).forEach { fail($0, error?.localizedDescription ?? "Couldn't connect") }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let d = p.identifier.uuidString
        // Anything still waiting on this device won't be answered now.
        (serviceWaits.removeValue(forKey: p.identifier) ?? []).forEach { fail($0.0, "Device disconnected") }
        for key in Array(charWaits.keys) where key.hasPrefix(d) { (charWaits.removeValue(forKey: key) ?? []).forEach { fail($0.0, "Device disconnected") } }
        for dict in [notifyWaits, writeWaits, readWaits] {
            for (key, ids) in dict where key.hasPrefix(d) { ids.forEach { fail($0, "Device disconnected") } }
        }
        notifyWaits = notifyWaits.filter { !$0.key.hasPrefix(d) }
        writeWaits = writeWaits.filter { !$0.key.hasPrefix(d) }
        readWaits = readWaits.filter { !$0.key.hasPrefix(d) }
        js("window.__tbBle.dropped(\(json(d)))")
        if !anyConnected { UIApplication.shared.isIdleTimerDisabled = false }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for (id, u) in serviceWaits.removeValue(forKey: p.identifier) ?? [] {
            if p.services?.contains(where: { same($0.uuid, u) }) == true { ok(id, ["id": "\(p.identifier.uuidString)|\(u)"]) }
            else { fail(id, "No Services matching UUID \(u) found in Device.") }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
        let key = "\(p.identifier.uuidString)|\(full(svc.uuid))"
        if let waits = charWaits.removeValue(forKey: key) {
            for (id, u) in waits {
                if svc.characteristics?.contains(where: { same($0.uuid, u) }) == true { ok(id, ["id": "\(key)|\(u)"]) }
                else { fail(id, "No Characteristics matching UUID \(u) found in Service.") }
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        guard let key = charKey(p, ch) else { return }
        for id in notifyWaits.removeValue(forKey: key) ?? [] {
            if let error { fail(id, error.localizedDescription) } else { ok(id) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let key = charKey(p, ch) else { return }
        let b64 = (ch.value ?? Data()).base64EncodedString()
        for id in readWaits.removeValue(forKey: key) ?? [] {
            if let error { fail(id, error.localizedDescription) } else { ok(id, b64) }
        }
        if ch.isNotifying && error == nil { js("window.__tbBle.value(\(json(key)),\(json(b64)))") }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        guard let key = charKey(p, ch), var waits = writeWaits[key], !waits.isEmpty else { return }
        let id = waits.removeFirst()
        writeWaits[key] = waits
        if let error { fail(id, error.localizedDescription) } else { ok(id) }
    }

    // MARK: lookups

    private func device(_ v: Any?) -> CBPeripheral? {
        guard let s = v as? String, let u = UUID(uuidString: s) else { return nil }
        if let p = peripherals[u] { return p }
        if let p = central.retrievePeripherals(withIdentifiers: [u]).first { peripherals[u] = p; p.delegate = self; return p }
        return nil
    }

    private func service(_ s: String) -> (CBPeripheral, CBService)? {
        let parts = s.split(separator: "|").map(String.init)
        guard parts.count >= 2, let p = device(parts[0]),
              let svc = p.services?.first(where: { same($0.uuid, parts[1]) }) else { return nil }
        return (p, svc)
    }

    private func characteristic(_ c: String) -> (CBPeripheral, CBCharacteristic)? {
        let parts = c.split(separator: "|").map(String.init)
        guard parts.count == 3, let (p, svc) = service(parts[0] + "|" + parts[1]),
              let ch = svc.characteristics?.first(where: { same($0.uuid, parts[2]) }) else { return nil }
        return (p, ch)
    }

    // The page and this side write UUIDs the same way (full, lower case), so a
    // characteristic's key can be rebuilt from CoreBluetooth's objects.
    private func charKey(_ p: CBPeripheral, _ ch: CBCharacteristic) -> String? {
        guard let svc = ch.service else { return nil }
        return "\(p.identifier.uuidString)|\(full(svc.uuid))|\(full(ch.uuid))"
    }

    // MARK: answering the page

    private func ok(_ id: Int, _ value: Any? = nil) {
        js("window.__tbBle.done(\(id),true,\(value.map(json) ?? "null"))")
    }

    private func fail(_ id: Int, _ message: String) {
        js("window.__tbBle.done(\(id),false,\(json(message)))")
    }

    private func js(_ code: String) {
        DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(code, completionHandler: nil) }
    }

    private func json(_ v: Any) -> String {
        if let s = v as? String, let d = try? JSONSerialization.data(withJSONObject: [s]),
           let t = String(data: d, encoding: .utf8) { return String(t.dropFirst().dropLast()) }
        if let d = try? JSONSerialization.data(withJSONObject: v), let t = String(data: d, encoding: .utf8) { return t }
        return "null"
    }
}

// UUIDs: the page uses full lower-case 128-bit strings; standard Bluetooth ones are
// compared in their short form so "0000180d-0000-1000-8000-00805f9b34fb" == 180D.
private let baseSuffix = "-0000-1000-8000-00805f9b34fb"

func cb(_ s: String) -> CBUUID {
    let l = s.lowercased()
    if l.count == 36, l.hasPrefix("0000"), l.hasSuffix(baseSuffix) {
        return CBUUID(string: String(l.dropFirst(4).prefix(4)))
    }
    return CBUUID(string: l)
}

func full(_ u: CBUUID) -> String {
    let s = u.uuidString.lowercased()
    if s.count == 4 { return "0000" + s + baseSuffix }
    if s.count == 8 { return s + baseSuffix }
    return s
}

func same(_ u: CBUUID, _ s: String) -> Bool { full(u) == full(cb(s)) }
