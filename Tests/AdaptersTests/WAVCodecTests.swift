import Testing
import Foundation
@testable import Adapters

@Suite struct WAVCodecTests {
    @Test func encodeProducesValidRiffHeader() {
        let samples: [Int16] = Array(repeating: 0, count: 16000)  // 1 second of silence at 16kHz
        let data = WAVCodec.encode(pcm: samples, sampleRate: 16000)
        let prefix = String(data: data.prefix(4), encoding: .ascii)
        let format = String(data: data.subdata(in: 8..<12), encoding: .ascii)
        #expect(prefix == "RIFF")
        #expect(format == "WAVE")
    }

    @Test func encodeAndDecodeRoundTrip() throws {
        let samples: [Int16] = (0..<8000).map { Int16(($0 % 1000) - 500) }
        let data = WAVCodec.encode(pcm: samples, sampleRate: 16000)
        let decoded = try #require(WAVCodec.decode(data))
        #expect(decoded.sampleRate == 16000)
        #expect(decoded.samples == samples)
    }

    @Test func decodeRejectsNonWAV() {
        let bogus = Data("Not a WAV file at all.".utf8)
        #expect(WAVCodec.decode(bogus) == nil)
    }

    @Test func encodeUses16BitMono() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768]
        let data = WAVCodec.encode(pcm: samples, sampleRate: 22050)
        let channels = Int(data[22]) | (Int(data[23]) << 8)
        #expect(channels == 1)
        let bps = Int(data[34]) | (Int(data[35]) << 8)
        #expect(bps == 16)
        let sr = UInt32(data[24]) | (UInt32(data[25]) << 8) | (UInt32(data[26]) << 16) | (UInt32(data[27]) << 24)
        #expect(sr == 22050)
    }
}
