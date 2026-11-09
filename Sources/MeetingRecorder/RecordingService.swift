import AVFoundation
import ScreenCaptureKit
import MeetingCore

@MainActor
final class RecordingService {
    private var microphone: AVAudioRecorder?
    private var stream: SCStream?
    private var output: CaptureOutput?
    private var routedMicrophone: RoutedMicrophone?
    private var stopping = false
    private(set) var captureFailure: String?

    var microphoneLevel: Double {
        guard let microphone else { return 0 }
        microphone.updateMeters()
        return pow(10, Double(microphone.averagePower(forChannel: 0)) / 20)
    }

    var microphoneIsRecording: Bool { microphone?.isRecording ?? false }

    func preparePermissions(for mode: RecordingMode) async throws {
        try await CapturePermissions.ensure(for: mode)
    }

    func applications() async throws -> [SCRunningApplication] {
        try await preparePermissions(for: .systemAudio)
        // Called only after an explicit user action; this can request screen/audio permission.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        return content.applications.filter {
            $0.processID != ProcessInfo.processInfo.processIdentifier && !$0.applicationName.isEmpty
        }.sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
    }

    func start(mode: RecordingMode, applicationID: Int32?, destination: URL, route: AudioInputRoute? = nil,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        guard microphone == nil, stream == nil, output == nil else {
            throw MeetingError.message("Ya hay una grabación activa.")
        }
        try await preparePermissions(for: mode)
        stopping = false
        captureFailure = nil
        if mode == .microphone, route == nil {
            let recorder = try AVAudioRecorder(url: destination, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ])
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw MeetingError.message("No se pudo iniciar la grabación del micrófono.")
            }
            microphone = recorder
            return
        }

        if mode == .microphone, let route {
            let output = try CaptureOutput(destination: destination, includeMicrophone: true, includeSystem: false) { [weak self] message in
                Task { @MainActor in
                    guard let self, !self.stopping else { return }
                    self.captureFailure = message
                    onFailure(message)
                }
            }
            let microphone = RoutedMicrophone()
            do { try microphone.start(route: route, output: output, onFailure: onFailure) }
            catch { await output.cancel(); throw error }
            self.routedMicrophone = microphone
            self.output = output
            return
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw MeetingError.message("No hay una pantalla disponible para capturar audio del sistema.")
        }
        let filter: SCContentFilter
        if mode.capturesWholeSystemAudio {
            // No application filter: include all system audio (not just the foreground app).
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else {
            guard let applicationID, let application = content.applications.first(where: { $0.processID == applicationID }) else {
                throw MeetingError.message("La aplicación seleccionada ya no está disponible. Actualiza la lista.")
            }
            filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        }
        let plan = ApplicationCapturePlan(mode: mode, hasSelectedInput: route != nil)
        let output = try CaptureOutput(destination: destination, includeMicrophone: plan.capturesMicrophone) { [weak self] message in
            Task { @MainActor in
                guard let self, !self.stopping else { return }
                self.captureFailure = message
                onFailure(message)
            }
        }
        let configuration = plan.configuration()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        for type in plan.outputTypes {
            try stream.addStreamOutput(output, type: type, sampleHandlerQueue: output.queue)
        }
        self.output = output
        self.stream = stream
        do {
            try await stream.startCapture()
            if plan.usesSeparateMicrophone {
                let microphone = RoutedMicrophone()
                try microphone.start(route: route, output: output, onFailure: onFailure)
                self.routedMicrophone = microphone
            }
            if let failure = await output.failureMessage() {
                try? await stream.stopCapture()
                throw MeetingError.message(failure)
            }
        } catch {
            routedMicrophone?.stop()
            routedMicrophone = nil
            try? await stream.stopCapture()
            self.stream = nil
            self.output = nil
            await output.cancel()
            throw error
        }
    }

    func stop() async throws {
        stopping = true
        routedMicrophone?.stop()
        routedMicrophone = nil
        if let microphone {
            microphone.stop()
            self.microphone = nil
            return
        }
        guard let output else { return }
        let stream = self.stream
        self.stream = nil
        self.output = nil
        var stopError: Error?
        do { try await stream?.stopCapture() }
        catch { stopError = error }
        // Finalize captured audio even when ScreenCaptureKit reports a stop error.
        try await output.finish()
        if let stopError { throw stopError }
    }
}

/// All writer state is confined to queue, including stream delegate errors.
final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    // Do not use the macOS-15-only SCStreamOutputType.microphone for internal audio.
    enum AudioSource { case audio, microphone }
    let queue = DispatchQueue(label: "MeetingRecorder.capture", qos: .userInitiated)
    private let writer: AVAssetWriter
    private let systemInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private let onFailure: @Sendable (String) -> Void
    private var firstTimestamp: CMTime?
    private var failure: String?

    init(destination: URL, includeMicrophone: Bool, includeSystem: Bool = true, onFailure: @escaping @Sendable (String) -> Void) throws {
        writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        systemInput = includeSystem ? AVAssetWriterInput(mediaType: .audio, outputSettings: settings) : nil
        microphoneInput = includeMicrophone ? AVAssetWriterInput(mediaType: .audio, outputSettings: settings) : nil
        self.onFailure = onFailure
        super.init()
        for input in [systemInput, microphoneInput].compactMap({ $0 }) {
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw MeetingError.message("No se pudo crear una pista de audio.") }
            writer.add(input)
        }
        // Fragmented MOV improves the chance of recovering media after an abnormal exit.
        writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio { append(sampleBuffer, type: .audio) }
        else if #available(macOS 15, *), type == .microphone { append(sampleBuffer, type: .microphone) }
    }

    /// Copy selected channels before the engine reuses its real-time buffer.
    func appendMicrophone(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, route: AudioInputRoute) {
        do {
            guard time.isHostTimeValid else { throw MeetingError.message("La entrada no entregó un reloj de audio válido.") }
            let samples = try route.monoSamples(buffer)
            guard !samples.isEmpty else { return }
            var format = AudioStreamBasicDescription(mSampleRate: buffer.format.sampleRate,
                mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
            var description: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format, layoutSize: 0,
                layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                formatDescriptionOut: &description) == noErr, let description else {
                throw MeetingError.message("No se pudo describir el audio de la entrada.")
            }
            var block: CMBlockBuffer?
            let size = samples.count * MemoryLayout<Float>.size
            guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                blockLength: size, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &block) == noErr, let block else {
                throw MeetingError.message("No se pudo reservar el búfer de entrada.")
            }
            let status = samples.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: size)
            }
            guard status == noErr else { throw MeetingError.message("No se pudo copiar el audio de entrada.") }
            var sample: CMSampleBuffer?
            let timestamp = CMTime(seconds: AVAudioTime.seconds(forHostTime: time.hostTime), preferredTimescale: 1_000_000_000)
            guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
                dataBuffer: block, formatDescription: description, sampleCount: samples.count,
                presentationTimeStamp: timestamp, packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
                let sample else { throw MeetingError.message("No se pudo crear la muestra de entrada.") }
            queue.async { self.append(sample, type: .microphone) }
        } catch {
            let message = error.localizedDescription
            queue.async { self.fail(message) }
        }
    }

    // Internal seam for deterministic tests with synthetic samples; always call on queue.
    func append(_ sampleBuffer: CMSampleBuffer, type: AudioSource) {
        let input: AVAssetWriterInput
        switch type {
        case .audio:
            guard let systemInput else { return }
            input = systemInput
        case .microphone:
            // Defense in depth: ignore unexpected mic samples before they can start a session.
            guard let microphoneInput else { return }
            input = microphoneInput
        }
        guard CMSampleBufferDataIsReady(sampleBuffer), CMSampleBufferGetNumSamples(sampleBuffer) > 0,
              failure == nil else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid else { return }
        if firstTimestamp == nil {
            guard writer.startWriting() else {
                fail(writer.error?.localizedDescription ?? "No se pudo escribir la grabación.")
                return
            }
            firstTimestamp = timestamp
            writer.startSession(atSourceTime: timestamp)
        }
        // Callbacks from separate sources can arrive slightly out of timestamp order.
        guard let firstTimestamp, timestamp >= firstTimestamp else { return }
        guard input.isReadyForMoreMediaData else {
            fail("El disco o el codificador no alcanzó a guardar el audio. Se detuvo para evitar pérdidas silenciosas.")
            return
        }
        if !input.append(sampleBuffer) {
            fail(writer.error?.localizedDescription ?? "No se pudo guardar una muestra de audio.")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.fail(error.localizedDescription) }
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard self.writer.status == .writing else {
                    continuation.resume(throwing: MeetingError.message(self.failure ?? self.writer.error?.localizedDescription ?? "No se recibieron muestras de audio."))
                    return
                }
                self.systemInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                self.writer.finishWriting {
                    self.queue.async {
                        if self.writer.status == .completed, self.failure == nil {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: MeetingError.message(self.failure ?? self.writer.error?.localizedDescription ?? "No se pudo finalizar el audio."))
                        }
                    }
                }
            }
        }
    }

    func failureMessage() async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.failure) }
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.writer.cancelWriting()
                continuation.resume()
            }
        }
    }

    private func fail(_ message: String) {
        guard failure == nil else { return }
        failure = message
        onFailure(message)
    }
}
