import AVFoundation

/// Decodes, mixes by the asset timeline and resamples with Apple's native codecs.
/// Bounded buffers: no full-meeting PCM array is kept in memory.
public actor AudioNormalizer {
    public init() {}

    public func normalize(source: URL, destination: URL) async throws -> Double {
        try await convert(source: source, destination: destination, sampleRate: 16_000, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
    }

    /// Mixes capture tracks to a single, audio-only AAC file. Keeps the source on failure.
    public func exportM4A(source: URL, destination: URL) async throws -> Double {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw MeetingError.message("El archivo de audio de destino ya existe. No se sobrescribió nada.")
        }
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".mantis-audio-\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: staged) }
        let duration = try await convert(source: source, destination: staged, sampleRate: 48_000, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000
        ])
        let asset = AVURLAsset(url: staged)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        let savedDuration = try await asset.load(.duration).seconds
        guard audio.count == 1, video.isEmpty, savedDuration > 0,
              abs(savedDuration - duration) < 0.25 else {
            throw MeetingError.message("No se pudo verificar el M4A. El audio temporal original se conserva.")
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staged, to: destination)
        return savedDuration
    }

    private func convert(source: URL, destination: URL, sampleRate: Double, settings: [String: Any]) async throws -> Double {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw MeetingError.message("El archivo no contiene pistas de audio.") }
        try Task.checkCancellation()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ])
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(1 / Float(tracks.count), at: .zero)
            return parameters
        }
        output.audioMix = mix
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MeetingError.message("No se pudo preparar la mezcla de audio.") }
        reader.add(output)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: true)
        guard reader.startReading() else { throw reader.error ?? MeetingError.message("No se pudo leer el audio.") }
        defer { reader.cancelReading() }
        var frames: Int64 = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0 else { continue }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw MeetingError.message("No hay memoria para convertir el audio sin perder muestras.")
            }
            buffer.frameLength = AVAudioFrameCount(count)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0,
                                                                     frameCount: Int32(count), into: buffer.mutableAudioBufferList)
            guard status == noErr else { throw MeetingError.message("No se pudo convertir el audio (\(status)).") }
            try file.write(from: buffer)
            frames += Int64(count)
        }
        guard reader.status == .completed else { throw reader.error ?? MeetingError.message("La lectura del audio no terminó.") }
        guard frames > 0 else { throw MeetingError.message("El audio está vacío.") }
        return Double(frames) / sampleRate
    }
}
