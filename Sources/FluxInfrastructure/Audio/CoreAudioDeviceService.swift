import Foundation
import CoreAudio
import FluxDomain

/// Lista dispositivos de áudio reais via CoreAudio e persiste a preferência
/// do usuário em UserDefaults (permitido por docs/05 — não é segredo).
///
/// Importante: NÃO altera o dispositivo padrão do sistema — a preferência é
/// do softphone e será aplicada ao fluxo de mídia pela engine real (Ciclo 5).
public actor CoreAudioDeviceService: AudioDeviceServiceProtocol {
    private static let inputKey = "audio.preferredInputDeviceUID"
    private static let outputKey = "audio.preferredOutputDeviceUID"

    /// Suite de UserDefaults isolada (testes usam uma exclusiva).
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    // MARK: - Listagem

    public func listInputDevices() async -> [AudioDevice] {
        devices(scope: kAudioDevicePropertyScopeInput, kind: .input)
    }

    public func listOutputDevices() async -> [AudioDevice] {
        devices(scope: kAudioDevicePropertyScopeOutput, kind: .output)
    }

    // MARK: - Preferência

    public func setInputDevice(_ id: String?) async throws {
        try setPreference(id, key: Self.inputKey, available: await listInputDevices())
    }

    public func setOutputDevice(_ id: String?) async throws {
        try setPreference(id, key: Self.outputKey, available: await listOutputDevices())
    }

    public func preferredInputDeviceId() async -> String? {
        defaults.string(forKey: Self.inputKey)
    }

    public func preferredOutputDeviceId() async -> String? {
        defaults.string(forKey: Self.outputKey)
    }

    private func setPreference(_ id: String?, key: String, available: [AudioDevice]) throws {
        guard let id else {
            defaults.removeObject(forKey: key)
            return
        }
        guard available.contains(where: { $0.id == id }) else {
            throw AudioDeviceServiceError.deviceNotFound(id: id)
        }
        defaults.set(id, forKey: key)
    }

    // MARK: - CoreAudio

    private enum DeviceKind {
        case input, output
    }

    private func devices(scope: AudioObjectPropertyScope, kind: DeviceKind) -> [AudioDevice] {
        let defaultID = defaultDeviceID(
            selector: kind == .input
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice
        )
        return allDeviceIDs().compactMap { deviceID in
            guard channelCount(device: deviceID, scope: scope) > 0,
                  let uid = stringProperty(device: deviceID, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(device: deviceID, selector: kAudioObjectPropertyName)
            else { return nil }
            return AudioDevice(
                id: uid,
                name: name,
                kind: kind == .input ? .input : .output,
                isDefault: deviceID == defaultID
            )
        }
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return [] }
        var ids = [AudioDeviceID](
            repeating: 0,
            count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &ids) == noErr
        else { return [] }
        return ids
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    /// Canais no escopo dado — decide se o dispositivo é entrada ou saída.
    private func channelCount(device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &dataSize, raw) == noErr
        else { return 0 }
        let bufferList = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func stringProperty(
        device: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
