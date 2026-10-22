import CoreBluetooth
import Foundation

// The Bluetooth half of nearby play. Multipeer Connectivity only finds phones
// over peer-to-peer Wi-Fi, so with Wi-Fi switched off it sees nobody; this
// finds and joins rooms over Bluetooth LE alone.
//
// The host is a peripheral: it advertises the room service, serves the room's
// info from a characteristic (pinging subscribers when it changes) and the PSM
// of an L2CAP channel. Guests scan, connect to each room to read its info, and
// open an L2CAP channel to join. Over the channel go length-prefixed frames:
// the guest's hello, the host's welcome, then the nearby messages.

/// What `NearbyBluetooth` reports to the nearby store. Ids are the other
/// phone's Bluetooth identifier.
protocol NearbyBluetoothDelegate: AnyObject {
    func bluetoothFound(_ id: UUID, info: [String: String])
    func bluetoothLost(_ id: UUID)
    /// Host: a guest says hello; whether to let them in.
    func bluetoothShouldAdmit(_ id: UUID, context: Data) -> Bool
    func bluetoothLink(_ id: UUID, connected: Bool)
    func bluetoothReceived(_ data: Data, from id: UUID)
}

final class NearbyBluetooth: NSObject {
    private static let service = CBUUID(string: "8E5C2B1A-4F7D-4C3E-9A61-2D0B7F1C5E90")
    private static let infoCharacteristic = CBUUID(string: "8E5C2B1B-4F7D-4C3E-9A61-2D0B7F1C5E90")
    private static let psmCharacteristic = CBUUID(string: "8E5C2B1C-4F7D-4C3E-9A61-2D0B7F1C5E90")
    private static let joinTimeout: Duration = .seconds(15)

    weak var delegate: NearbyBluetoothDelegate?

    // Hosting.
    private var peripheralManager: CBPeripheralManager?
    private var infoCharacteristic: CBMutableCharacteristic?
    private var psm: CBL2CAPPSM?
    /// The room's info while it takes players; nil when not hosting, full or started.
    private var hostedInfo: [String: String]?
    private var infoVersion: UInt8 = 0

    // Looking and joining.
    private var centralManager: CBCentralManager?
    private var browsing = false
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var psms: [UUID: CBL2CAPPSM] = [:]
    /// The room this guest joined or is joining.
    private var hostID: UUID?
    private var joinContext: Data?
    private var joinTimer: Task<Void, Never>?

    private var channels: [UUID: Channel] = [:]

    var connectedIDs: [UUID] { channels.values.filter(\.admitted).map(\.id) }

    // MARK: Hosting

    /// Advertises a room with `info`, or stops advertising when nil.
    func host(_ info: [String: String]?) {
        hostedInfo = info
        if info != nil, peripheralManager == nil {
            // Asks for Bluetooth access; the room goes up once it's powered on.
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
            return
        }
        updateHosting()
    }

    private func updateHosting() {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }
        if infoCharacteristic == nil {
            let info = CBMutableCharacteristic(type: Self.infoCharacteristic, properties: [.read, .notify],
                                               value: nil, permissions: .readable)
            let psm = CBMutableCharacteristic(type: Self.psmCharacteristic, properties: .read,
                                              value: nil, permissions: .readable)
            let service = CBMutableService(type: Self.service, primary: true)
            service.characteristics = [info, psm]
            manager.add(service)
            manager.publishL2CAPChannel(withEncryption: false)
            infoCharacteristic = info
        }
        if hostedInfo != nil, psm != nil {
            if !manager.isAdvertising {
                manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.service]])
            }
        } else if manager.isAdvertising {
            manager.stopAdvertising()
        }
        // Guests looking at the room read it again.
        infoVersion &+= 1
        if let infoCharacteristic {
            manager.updateValue(Data([infoVersion]), for: infoCharacteristic, onSubscribedCentrals: nil)
        }
    }

    // MARK: Looking and joining

    func look() {
        browsing = true
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else {
            scan()
        }
    }

    func stopLooking() {
        browsing = false
        centralManager?.stopScan()
        for (id, peripheral) in peripherals where id != hostID {
            centralManager?.cancelPeripheralConnection(peripheral)
            peripherals[id] = nil
            psms[id] = nil
        }
    }

    private func scan() {
        guard browsing, let central = centralManager, central.state == .poweredOn else { return }
        central.stopScan()
        central.scanForPeripherals(withServices: [Self.service])
    }

    /// Asks the room at `id` to let this player in; `bluetoothLink` says how it went.
    func join(_ id: UUID, context: Data) {
        guard let peripheral = peripherals[id], peripheral.state == .connected, let psm = psms[id], psm != 0 else {
            Task { self.delegate?.bluetoothLink(id, connected: false) }
            return
        }
        hostID = id
        joinContext = context
        peripheral.openL2CAPChannel(psm)
        joinTimer?.cancel()
        joinTimer = Task {
            try? await Task.sleep(for: Self.joinTimeout)
            guard !Task.isCancelled, self.hostID == id, self.channels[id]?.admitted != true else { return }
            self.joinFailed(id)
        }
    }

    private func joinFailed(_ id: UUID) {
        guard hostID == id else { return }
        hostID = nil
        joinContext = nil
        joinTimer?.cancel()
        channels.removeValue(forKey: id)?.close(reporting: false)
        delegate?.bluetoothLink(id, connected: false)
    }

    // MARK: Talking

    func send(_ data: Data, to ids: [UUID]? = nil) {
        for channel in channels.values where channel.admitted && (ids?.contains(channel.id) ?? true) {
            channel.send(.message, data)
        }
    }

    /// Leaves the room: stops advertising and hangs up every channel, after
    /// sending what's queued, without reporting it.
    func disconnect() {
        host(nil)
        hostID = nil
        joinContext = nil
        joinTimer?.cancel()
        for channel in channels.values { channel.close(reporting: false) }
        channels = [:]
        guard !browsing else { return }
        // Give the last message a moment before the link goes.
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard !self.browsing, self.hostID == nil else { return }
            for peripheral in self.peripherals.values { self.centralManager?.cancelPeripheralConnection(peripheral) }
            self.peripherals = [:]
            self.psms = [:]
        }
    }

    private func open(_ l2cap: CBL2CAPChannel, id: UUID) -> Channel {
        channels.removeValue(forKey: id)?.close(reporting: false)
        let channel = Channel(l2cap, id: id)
        channel.onFrame = { [weak self, weak channel] kind, payload in
            guard let self, let channel else { return }
            self.received(kind, payload, on: channel)
        }
        channel.onClose = { [weak self, weak channel] in
            guard let self, let channel else { return }
            self.closed(channel)
        }
        channels[id] = channel
        channel.open()
        return channel
    }

    private func received(_ kind: Channel.Kind, _ payload: Data, on channel: Channel) {
        switch kind {
        case .hello:
            // Host: a guest asks to join.
            guard hostedInfo != nil, delegate?.bluetoothShouldAdmit(channel.id, context: payload) == true else {
                channels[channel.id] = nil
                channel.close(reporting: false)
                return
            }
            channel.admitted = true
            channel.send(.welcome)
            delegate?.bluetoothLink(channel.id, connected: true)
        case .welcome:
            // Guest: the host let us in.
            guard hostID == channel.id, !channel.admitted else { return }
            channel.admitted = true
            joinTimer?.cancel()
            delegate?.bluetoothLink(channel.id, connected: true)
        case .message:
            guard channel.admitted else { return }
            delegate?.bluetoothReceived(payload, from: channel.id)
        }
    }

    private func closed(_ channel: Channel) {
        guard channels[channel.id] === channel else { return }
        channels[channel.id] = nil
        if hostID == channel.id {
            hostID = nil
            joinContext = nil
            joinTimer?.cancel()
            delegate?.bluetoothLink(channel.id, connected: false)
        } else if channel.admitted {
            delegate?.bluetoothLink(channel.id, connected: false)
        }
    }
}

// MARK: - Host callbacks

// Both managers run on the main queue, so these are on the main actor.

extension NearbyBluetooth: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            updateHosting()
        } else {
            // Bluetooth went off: the service and channel are gone with it.
            infoCharacteristic = nil
            psm = nil
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        guard error == nil else { return }
        psm = PSM
        updateHosting()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        let value: Data
        switch request.characteristic.uuid {
        case Self.infoCharacteristic:
            value = (try? JSONEncoder().encode(hostedInfo ?? [:])) ?? Data()
        case Self.psmCharacteristic:
            value = withUnsafeBytes(of: (psm ?? 0).littleEndian) { Data($0) }
        default:
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset..<value.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel, error == nil else { return }
        _ = open(channel, id: channel.peer.identifier)
    }
}

// MARK: - Guest callbacks

extension NearbyBluetooth: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scan()
        } else {
            for id in peripherals.keys { delegate?.bluetoothLost(id) }
            peripherals = [:]
            psms = [:]
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard browsing, peripherals[peripheral.identifier] == nil else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripherals[peripheral.identifier] = nil
        // Seen peripherals aren't reported again until the scan restarts.
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = peripheral.identifier
        peripherals[id] = nil
        psms[id] = nil
        delegate?.bluetoothLost(id)
        if hostID == id, channels[id] == nil { joinFailed(id) }
        scan()
    }
}

extension NearbyBluetooth: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else {
            centralManager?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.infoCharacteristic, Self.psmCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            peripheral.readValue(for: characteristic)
            if characteristic.uuid == Self.infoCharacteristic {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let id = peripheral.identifier
        switch characteristic.uuid {
        case Self.psmCharacteristic where value.count >= 2:
            psms[id] = CBL2CAPPSM(value[value.startIndex]) | CBL2CAPPSM(value[value.startIndex + 1]) << 8
        case Self.infoCharacteristic where value.count <= 1:
            // The host's ping: the room changed, read it again.
            peripheral.readValue(for: characteristic)
        case Self.infoCharacteristic:
            guard let info = try? JSONDecoder().decode([String: String].self, from: value) else { return }
            if info.isEmpty {
                delegate?.bluetoothLost(id)
            } else {
                delegate?.bluetoothFound(id, info: info)
            }
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        let id = peripheral.identifier
        guard hostID == id, let joinContext else { return }
        guard let channel, error == nil else {
            joinFailed(id)
            return
        }
        open(channel, id: id).send(.hello, joinContext)
    }
}

// MARK: - Channel

/// One L2CAP channel, sending and receiving whole frames: a 4-byte big-endian
/// length, then a kind byte and the payload.
private final class Channel: NSObject {
    enum Kind: UInt8 { case hello, welcome, message }

    private static let maxFrame = 4 << 20

    let id: UUID
    var admitted = false
    var onFrame: ((Kind, Data) -> Void)?
    var onClose: (() -> Void)?

    private let channel: CBL2CAPChannel
    private var inbox = Data()
    private var outbox = Data()
    private var closing = false
    private var closed = false
    /// Kept alive while open, so a channel being hung up can finish sending.
    private var keepAlive: Channel?

    init(_ channel: CBL2CAPChannel, id: UUID) {
        self.channel = channel
        self.id = id
    }

    private var streams: [Stream] { [channel.inputStream, channel.outputStream].compactMap { $0 } }

    func open() {
        keepAlive = self
        for stream in streams {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .default)
            stream.open()
        }
    }

    func send(_ kind: Kind, _ payload: Data = Data()) {
        guard !closing, !closed else { return }
        let length = UInt32(payload.count + 1)
        outbox.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        outbox.append(kind.rawValue)
        outbox.append(payload)
        flush()
    }

    /// Hangs up once what's queued is sent (or after a couple of seconds).
    func close(reporting: Bool) {
        if !reporting { onClose = nil }
        guard !closing, !closed else { return }
        closing = true
        flush()
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.finish()
        }
    }

    private func flush() {
        guard let output = channel.outputStream else { return }
        while !outbox.isEmpty, output.hasSpaceAvailable {
            let written = outbox.withUnsafeBytes { bytes in
                output.write(bytes.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytes.count)
            }
            guard written > 0 else { break }
            outbox = Data(outbox.dropFirst(written))
        }
        if closing, outbox.isEmpty { finish() }
    }

    private func read() {
        guard let input = channel.inputStream else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while input.hasBytesAvailable {
            let count = input.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            inbox.append(buffer, count: count)
        }
        while inbox.count >= 4 {
            let length = inbox.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= Self.maxFrame else { finish(); return }
            guard inbox.count >= 4 + length else { break }
            let frame = Data(inbox.dropFirst(4).prefix(length))
            inbox = Data(inbox.dropFirst(4 + length))
            guard let kind = Kind(rawValue: frame[frame.startIndex]) else { continue }
            onFrame?(kind, Data(frame.dropFirst()))
            if closed { return }
        }
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        for stream in streams {
            stream.delegate = nil
            stream.close()
            stream.remove(from: .main, forMode: .default)
        }
        let onClose = onClose
        self.onClose = nil
        onFrame = nil
        onClose?()
        keepAlive = nil
    }
}

extension Channel: StreamDelegate {
    func stream(_ stream: Stream, handle event: Stream.Event) {
        switch event {
        case .hasBytesAvailable: read()
        case .hasSpaceAvailable: flush()
        case .errorOccurred, .endEncountered: finish()
        default: break
        }
    }
}
