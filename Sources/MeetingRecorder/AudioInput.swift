import AVFoundation
import AudioToolbox
import CoreAudio
import MeetingCore

struct AudioInputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let channelCount: Int
    let deviceID: AudioDeviceID

    static func available() throws -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            throw MeetingError.message("No se pudieron enumerar las entradas de audio.")
        }
        guard size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw MeetingError.message("No se pudieron leer las entradas de audio.") }
        return ids.compactMap { id in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                    mScope: kAudioDevicePropertyScopeInput,
                                                    mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
            let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { pointer.deallocate() }
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr else { return nil }
            let buffers = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
            let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { return nil }
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                        mElement: kAudioObjectPropertyElementMain)
                var value: Unmanaged<CFString>?
                var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
                return value?.takeRetainedValue() as String?
            }
            guard let uid = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: uid, name: name, channelCount: channels, deviceID: id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Channel numbers are zero-based internally. Only selected channels reach disk.
struct AudioInputRoute: Equatable {
    let deviceUID: String
    let channels: [Int]

    func validate(channelCount: Int) throws {
        guard !channels.isEmpty, Set(channels).count == channels.count,
              channels.allSatisfy({ $0 >= 0 && $0 < channelCount }) else {
            throw MeetingError.message("Selecciona al menos un canal disponible de la entrada de audio.")
        }
    }

    func monoSamples(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        try validate(channelCount: Int(buffer.format.channelCount))
        guard buffer.format.commonFormat == .pcmFormatFloat32, let data = buffer.floatChannelData else {
            throw MeetingError.message("La entrada no entregó audio Float32 compatible.")
        }
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        return (0..<Int(buffer.frameLength)).map { frame in
            channels.reduce(Float(0)) { sum, channel in
                sum + (buffer.format.isInterleaved ? data[0][frame * stride + channel] : data[channel][frame])
            } / Float(channels.count)
        }
    }
}

/// Private engine: changes only this app's input, never the system default device.
@MainActor
final class RoutedMicrophone {
    private let engine = AVAudioEngine()
    private var configurationObserver: NSObjectProtocol?

    func start(route: AudioInputRoute?, output: CaptureOutput,
               onFailure: @escaping @MainActor (String) -> Void) throws {
        let input = engine.inputNode
        if let route {
            guard let device = try AudioInputDevice.available().first(where: { $0.id == route.deviceUID }) else {
                throw MeetingError.message("La entrada seleccionada se desconectó. Actualiza los dispositivos.")
            }
            try route.validate(channelCount: device.channelCount)
            guard let unit = input.audioUnit else { throw MeetingError.message("No se pudo abrir la entrada de audio.") }
            var id = device.deviceID
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                             0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw MeetingError.message("No se pudo seleccionar la interfaz de audio (\(status)).") }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw MeetingError.message("La entrada de audio no tiene una frecuencia válida.") }
        // A nil route uses the engine's default input without altering the system device.
        let channels = route ?? AudioInputRoute(deviceUID: "system-default", channels: Array(0..<Int(format.channelCount)))
        try channels.validate(channelCount: Int(format.channelCount))
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, time in
            output.appendMicrophone(buffer, at: time, route: channels)
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                                       object: engine, queue: .main) { _ in
            Task { @MainActor in onFailure("Cambió o se desconectó la entrada de audio. Se detuvo la grabación para evitar pérdidas.") }
        }
        do { try engine.start() }
        catch { stop(); throw error }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}
