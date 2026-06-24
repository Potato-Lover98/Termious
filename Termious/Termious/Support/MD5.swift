import Foundation

/// Minimal MD5 implementation (RFC 1321). Used by the `hash --md5` command
/// since Apple's CryptoKit doesn't expose MD5.
struct MD5 {
    func compute(_ data: Data) -> [UInt8] {
        var message = [UInt8](data)
        let originalLength = UInt64(message.count) * 8

        // Padding
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0x00)
        }
        for i in 0..<8 {
            message.append(UInt8((originalLength >> (8 * i)) & 0xFF))
        }

        // Initial state
        var a0: UInt32 = 0x67452301
        var b0: UInt32 = 0xefcdab89
        var c0: UInt32 = 0x98badcfe
        var d0: UInt32 = 0x10325476

        // Per-round shift amounts
        let s: [UInt32] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
            5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
            4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
        ]
        // Constants
        let K: [UInt32] = (0..<64).map { UInt32(floor(abs(sin(Double($0 + 1))) * pow(2.0, 32.0))) }

        // Process each 512-bit chunk
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var M: [UInt32] = []
            for i in 0..<16 {
                let off = chunkStart + i * 4
                let v = UInt32(message[off])
                    | (UInt32(message[off + 1]) << 8)
                    | (UInt32(message[off + 2]) << 16)
                    | (UInt32(message[off + 3]) << 24)
                M.append(v)
            }

            var A = a0, B = b0, C = c0, D = d0
            for i in 0..<64 {
                var F: UInt32 = 0
                var g: Int = 0
                if i < 16 {
                    F = (B & C) | (~B & D); g = i
                } else if i < 32 {
                    F = (D & B) | (~D & C); g = (5 * i + 1) % 16
                } else if i < 48 {
                    F = B ^ C ^ D; g = (3 * i + 5) % 16
                } else {
                    F = C ^ (B | ~D); g = (7 * i) % 16
                }
                F = F &+ A &+ K[i] &+ M[g]
                A = D
                D = C
                C = B
                B = B &+ leftRotate(F, by: s[i])
            }
            a0 = a0 &+ A
            b0 = b0 &+ B
            c0 = c0 &+ C
            d0 = d0 &+ D
        }

        var result: [UInt8] = []
        for v in [a0, b0, c0, d0] {
            for i in 0..<4 {
                result.append(UInt8((v >> (8 * i)) & 0xFF))
            }
        }
        return result
    }

    private func leftRotate(_ value: UInt32, by shift: UInt32) -> UInt32 {
        (value << shift) | (value >> (32 - shift))
    }
}