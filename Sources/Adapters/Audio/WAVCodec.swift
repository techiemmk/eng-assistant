import Foundation

/// Minimal 16-bit mono PCM WAV encoder/decoder. No metadata chunks, no
/// floating-point support — just what STT/TTS round-tripping needs.
public enum WAVCodec {
    public static func encode(pcm samples: [Int16], sampleRate: Int) -> Data {
        let dataByteCount = samples.count * 2
        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        // RIFF header
        data.append(contentsOf: Array("RIFF".utf8))
        data.append(uint32: UInt32(36 + dataByteCount))
        data.append(contentsOf: Array("WAVE".utf8))

        // fmt subchunk
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(uint32: 16)                              // subchunk1 size for PCM
        data.append(uint16: 1)                               // audio format = PCM
        data.append(uint16: 1)                               // channels = mono
        data.append(uint32: UInt32(sampleRate))
        data.append(uint32: UInt32(sampleRate * 2))          // byte rate (sampleRate * channels * bytesPerSample)
        data.append(uint16: 2)                               // block align (channels * bytesPerSample)
        data.append(uint16: 16)                              // bits per sample

        // data subchunk
        data.append(contentsOf: Array("data".utf8))
        data.append(uint32: UInt32(dataByteCount))
        for sample in samples {
            data.append(uint16: UInt16(bitPattern: sample))
        }
        return data
    }

    public static func decode(_ data: Data) -> (samples: [Int16], sampleRate: Int)? {
        guard data.count >= 44 else { return nil }
        guard data.subdata(in: 0..<4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WAVE".utf8) else {
            return nil
        }
        var cursor = 12
        var dataChunkOffset: Int?
        var dataChunkSize: Int = 0
        while cursor + 8 <= data.count {
            let chunkID = data.subdata(in: cursor..<cursor + 4)
            let size = Int(data.uint32(at: cursor + 4))
            if chunkID == Data("data".utf8) {
                dataChunkOffset = cursor + 8
                dataChunkSize = size
                break
            }
            cursor += 8 + size
        }
        guard let off = dataChunkOffset else { return nil }
        let sampleRate = Int(data.uint32(at: 24))
        let bytesAvailable = min(dataChunkSize, data.count - off)
        let sampleCount = bytesAvailable / 2
        var samples = [Int16](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let lo = data[off + i * 2]
            let hi = data[off + i * 2 + 1]
            let raw = UInt16(lo) | (UInt16(hi) << 8)
            samples[i] = Int16(bitPattern: raw)
        }
        return (samples, sampleRate)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
