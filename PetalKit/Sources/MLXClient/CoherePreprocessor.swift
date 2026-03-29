import Accelerate
import AVFoundation
import Foundation

/// Computes 128-bin log mel-spectrogram features for Cohere Transcribe.
///
/// Matches NeMo's FilterbankFeatures with config:
/// - sample_rate: 16000
/// - n_fft: 512
/// - win_length: 400  (25 ms)
/// - hop_length: 160  (10 ms)
/// - n_mels: 128
/// - preemphasis: 0.97
/// - dither: 1e-5
/// - normalize: per_feature
/// - log: true
enum CoherePreprocessor {
    static let sampleRate: Double = 16000
    static let nFFT = 512
    static let winLength = 400
    static let hopLength = 160
    static let nMels = 128
    static let preemphasis: Float = 0.97
    static let ditherAmount: Float = 1e-5

    struct MelFeatures {
        /// Flat array of shape [nMels, timeFrames] in row-major order.
        let data: [Float]
        let nMels: Int
        let timeFrames: Int
    }

    /// Loads audio from a URL, resamples to 16kHz mono, and computes mel features.
    static func extractFeatures(from audioURL: URL) throws -> MelFeatures {
        let samples = try loadAudio16kHzMono(from: audioURL)
        return computeMelSpectrogram(samples: samples)
    }

    // MARK: - Audio Loading

    private static func loadAudio16kHzMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let inputSampleRate = file.fileFormat.sampleRate
        let inputLength = file.length
        let outputLength = AVAudioFrameCount(Double(inputLength) * sampleRate / inputSampleRate)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputLength) else {
            throw CoherePreprocessorError.bufferAllocationFailed
        }

        if inputSampleRate == sampleRate && file.fileFormat.channelCount == 1 {
            try file.read(into: buffer)
        } else {
            let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputSampleRate,
                channels: 1,
                interleaved: false
            )!
            let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(inputLength)
            )!
            try file.read(into: sourceBuffer)

            guard let converter = AVAudioConverter(from: sourceFormat, to: format) else {
                throw CoherePreprocessorError.converterCreationFailed
            }
            var isDone = false
            converter.convert(to: buffer, error: nil) { _, outStatus in
                if isDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                isDone = true
                outStatus.pointee = .haveData
                return sourceBuffer
            }
        }

        guard let channelData = buffer.floatChannelData else {
            throw CoherePreprocessorError.noAudioData
        }

        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    // MARK: - Mel Spectrogram

    private static func computeMelSpectrogram(samples: [Float]) -> MelFeatures {
        var signal = samples

        // 1. Dither
        if ditherAmount > 0 {
            for i in signal.indices {
                signal[i] += Float.random(in: -ditherAmount...ditherAmount)
            }
        }

        // 2. Pre-emphasis
        if preemphasis > 0 {
            for i in stride(from: signal.count - 1, through: 1, by: -1) {
                signal[i] -= preemphasis * signal[i - 1]
            }
            signal[0] *= (1.0 - preemphasis)
        }

        // 3. STFT
        let numFrames = max(0, (signal.count - winLength) / hopLength) + 1
        let fftSize = nFFT
        let halfFFT = fftSize / 2 + 1 // 257 frequency bins

        // Hann window
        var window = [Float](repeating: 0, count: winLength)
        vDSP_hann_window(&window, vDSP_Length(winLength), Int32(vDSP_HANN_NORM))

        // Pad window to FFT size
        var paddedWindow = [Float](repeating: 0, count: fftSize)
        paddedWindow.replaceSubrange(0..<winLength, with: window)

        // Set up FFT
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return MelFeatures(data: [], nMels: nMels, timeFrames: 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Power spectrum for each frame
        var powerSpectra = [[Float]](repeating: [Float](repeating: 0, count: halfFFT), count: numFrames)

        // Temporary buffers for FFT
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)

        for frame in 0..<numFrames {
            let start = frame * hopLength
            var frameSamples = [Float](repeating: 0, count: fftSize)

            // Copy and window
            let copyLen = min(winLength, signal.count - start)
            if copyLen > 0 {
                for i in 0..<copyLen {
                    frameSamples[i] = signal[start + i] * window[i]
                }
            }

            // Convert to split complex for vDSP FFT
            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    frameSamples.withUnsafeBufferPointer { frameBuf in
                        frameBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                            var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                        }
                    }

                    // FFT
                    var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }

            // Compute power spectrum (magnitude squared)
            // DC component
            powerSpectra[frame][0] = (realPart[0] * realPart[0]) / Float(fftSize * fftSize)
            // Nyquist component
            powerSpectra[frame][halfFFT - 1] = (imagPart[0] * imagPart[0]) / Float(fftSize * fftSize)
            // Other bins
            let scale = 1.0 / Float(fftSize * fftSize)
            for i in 1..<(halfFFT - 1) {
                powerSpectra[frame][i] = (realPart[i] * realPart[i] + imagPart[i] * imagPart[i]) * scale
            }
        }

        // 4. Mel filterbank
        let melFilterbank = createMelFilterbank(
            nMels: nMels,
            nFFT: fftSize,
            sampleRate: Float(sampleRate),
            fMin: 0,
            fMax: Float(sampleRate) / 2
        )

        // Apply filterbank: [nMels, halfFFT] x [halfFFT, numFrames] = [nMels, numFrames]
        var melSpectrogram = [Float](repeating: 0, count: nMels * numFrames)
        for m in 0..<nMels {
            for t in 0..<numFrames {
                var sum: Float = 0
                for f in 0..<halfFFT {
                    sum += melFilterbank[m * halfFFT + f] * powerSpectra[t][f]
                }
                melSpectrogram[m * numFrames + t] = sum
            }
        }

        // 5. Log
        let logFloor: Float = 1e-10
        for i in melSpectrogram.indices {
            melSpectrogram[i] = log(max(melSpectrogram[i], logFloor))
        }

        // 6. Per-feature normalization (normalize each mel bin to zero mean, unit variance)
        melSpectrogram.withUnsafeMutableBufferPointer { buf in
            for m in 0..<nMels {
                let offset = m * numFrames
                guard numFrames > 0 else { continue }
                let ptr = buf.baseAddress! + offset

                var mean: Float = 0
                vDSP_meanv(ptr, 1, &mean, vDSP_Length(numFrames))

                var negMean = -mean
                vDSP_vsadd(ptr, 1, &negMean, ptr, 1, vDSP_Length(numFrames))

                var sumSq: Float = 0
                vDSP_svesq(ptr, 1, &sumSq, vDSP_Length(numFrames))
                let variance = sumSq / Float(numFrames)
                let std = sqrt(variance + 1e-10)

                if std > 0 {
                    var invStd = 1.0 / std
                    vDSP_vsmul(ptr, 1, &invStd, ptr, 1, vDSP_Length(numFrames))
                }
            }
        }

        return MelFeatures(data: melSpectrogram, nMels: nMels, timeFrames: numFrames)
    }

    // MARK: - Mel Filterbank

    /// Creates a mel filterbank matrix of shape [nMels, nFFT/2 + 1].
    private static func createMelFilterbank(
        nMels: Int,
        nFFT: Int,
        sampleRate: Float,
        fMin: Float,
        fMax: Float
    ) -> [Float] {
        let halfFFT = nFFT / 2 + 1

        // Hz to Mel conversion (HTK formula)
        func hzToMel(_ hz: Float) -> Float {
            2595.0 * log10(1.0 + hz / 700.0)
        }
        func melToHz(_ mel: Float) -> Float {
            700.0 * (pow(10.0, mel / 2595.0) - 1.0)
        }

        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)

        // Equally spaced mel points
        var melPoints = [Float](repeating: 0, count: nMels + 2)
        for i in 0...(nMels + 1) {
            melPoints[i] = melMin + Float(i) * (melMax - melMin) / Float(nMels + 1)
        }

        // Convert back to Hz and then to FFT bin indices
        var fftBins = [Float](repeating: 0, count: nMels + 2)
        for i in 0...(nMels + 1) {
            let hz = melToHz(melPoints[i])
            fftBins[i] = hz * Float(nFFT) / sampleRate
        }

        // Build triangular filters
        var filterbank = [Float](repeating: 0, count: nMels * halfFFT)
        for m in 0..<nMels {
            let left = fftBins[m]
            let center = fftBins[m + 1]
            let right = fftBins[m + 2]

            for f in 0..<halfFFT {
                let freq = Float(f)
                if freq >= left && freq <= center && center > left {
                    filterbank[m * halfFFT + f] = (freq - left) / (center - left)
                } else if freq > center && freq <= right && right > center {
                    filterbank[m * halfFFT + f] = (right - freq) / (right - center)
                }
            }
        }

        return filterbank
    }
}

enum CoherePreprocessorError: LocalizedError {
    case bufferAllocationFailed
    case converterCreationFailed
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer for resampling."
        case .converterCreationFailed:
            return "Failed to create audio converter for resampling to 16kHz."
        case .noAudioData:
            return "No audio data available after loading."
        }
    }
}
