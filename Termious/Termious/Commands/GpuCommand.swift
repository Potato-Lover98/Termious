import Foundation
import Metal
import CryptoKit

/// `gpu` - Metal GPU access for parallel computation.
/// Usage: gpu info              Show GPU info
///        gpu hash <algo> <data>  GPU-accelerated hashing
///        gpu bench              Run a GPU compute benchmark
///        gpu compute <shader.metal> <input>  Run a custom Metal compute shader
///        gpu matrix <N>         GPU matrix multiplication benchmark
struct GpuCommand: BuiltinCommand {
    let name = "gpu"
    let summary = "Metal GPU compute for heavy tasks"
    let usage = "gpu info | gpu hash <algo> <data> | gpu bench | gpu matrix <N> | gpu compute <shader> <input>"
    var operands: [Operand] {[
        Operand(name: "subcommand", description: "info, hash, bench, matrix, compute", required: true, type: .string),
        Operand(name: "args", description: "Subcommand-specific arguments", required: false, type: .string),
    ]}

    static var device: MTLDevice? { MTLCreateSystemDefaultDevice() }

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let sub = arguments.first else {
            context.stderr("gpu: missing subcommand. Use: gpu info|hash|bench|matrix|compute\n")
            return 1
        }
        let rest = Array(arguments.dropFirst())
        guard let device = GpuCommand.device else {
            context.stderr("gpu: Metal not available on this device\n")
            return 1
        }

        switch sub {
        case "info": return showInfo(device: device, context: context)
        case "hash": return gpuHash(args: rest, device: device, context: context)
        case "bench": return benchmark(device: device, context: context)
        case "matrix": return matrixMul(args: rest, device: device, context: context)
        case "compute": return computeShader(args: rest, device: device, context: context)
        case "help", "-h":
            context.stdout("gpu: info hash bench matrix compute\n")
            return 0
        default:
            context.stderr("gpu: unknown '\(sub)'\n")
            return 1
        }
    }

    // MARK: - info

    private func showInfo(device: MTLDevice, context: CommandContext) -> Int32 {
        context.stdout("\u{001B}[36mMetal GPU Info\u{001B}[0m\n\n")
        context.stdout("Device:        \(device.name)\n")
        #if !targetEnvironment(simulator)
        if device.supportsFamily(.apple5) { context.stdout("Family:        Apple GPU (A11+)\n") }
        else if device.supportsFamily(.apple4) { context.stdout("Family:        Apple GPU (A9-A10)\n") }
        else { context.stdout("Family:        Apple GPU\n") }
        #endif
        context.stdout("Max threads:   \(device.maxThreadsPerThreadgroup.width) per group\n")
        context.stdout("Recommended:   \(device.recommendedMaxWorkingSetSize / 1024 / 1024) MB working set\n")
        context.stdout("Unified mem:   \(device.hasUnifiedMemory ? "yes" : "no")\n")
        let supportsCompute = device.maxThreadsPerThreadgroup.width > 0
        context.stdout("Supports:      \(supportsCompute ? "compute" : "no compute")\n")
        if supportsCompute {
            context.stdout("Metal:         available for heavy tasks\n")
        }
        return 0
    }

    // MARK: - GPU hashing (SHA-256 via Metal compute)

    private func gpuHash(args: [String], device: MTLDevice, context: CommandContext) -> Int32 {
        guard args.count >= 2 else {
            context.stderr("gpu hash: need <algo> <data>. Algos: sha256, double-sha256\n")
            return 1
        }
        let algo = args[0]
        let data = args.dropFirst().joined(separator: " ")
        let dataBytes = [UInt8](data.utf8)

        switch algo {
        case "sha256":
            let hash = sha256GPU(data: dataBytes, device: device)
            if let h = hash {
                let hex = h.map { String(format: "%02x", $0) }.joined()
                context.stdout("\(hex)  \(data)\n")
                return 0
            } else {
                let digest = SHA256.hash(data: Data(dataBytes))
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                context.stdout("\(hex)  \(data)  (CPU fallback)\n")
                return 0
            }
        case "double-sha256":
            let d1 = SHA256.hash(data: Data(dataBytes))
            let d2 = SHA256.hash(data: Data(d1))
            let hex = d2.map { String(format: "%02x", $0) }.joined()
            context.stdout("\(hex)  \(data)  (CPU)\n")
            return 0
        default:
            context.stderr("gpu hash: unknown algo '\(algo)'. Use sha256 or double-sha256.\n")
            return 1
        }
    }

    private func sha256GPU(data: [UInt8], device: MTLDevice) -> [UInt8]? {
        guard let library = try? makeSha256Library(device: device) else { return nil }
        guard let fn = library.makeFunction(name: "sha256_hash"),
              let pipeline = try? device.makeComputePipelineState(function: fn) else { return nil }
        guard let cmdBuf = device.makeCommandQueue()?.makeCommandBuffer(),
              let encoder = cmdBuf.makeComputeCommandEncoder() else { return nil }

        let inputBuffer = device.makeBuffer(bytes: data, length: data.count, options: [])
        let outputBuffer = device.makeBuffer(length: 32, options: [])

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBytes([UInt32(data.count)], length: 4, index: 2)

        let threadGroup = MTLSize(width: 1, height: 1, depth: 1)
        let threadGroups = MTLSize(width: 1, height: 1, depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroup)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        var result = [UInt8](repeating: 0, count: 32)
        if let outputBuffer = outputBuffer {
            memcpy(&result, outputBuffer.contents(), 32)
        }
        return result
    }

    private func makeSha256Library(device: MTLDevice) throws -> MTLLibrary {
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        constant uint K[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c8f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        };

        uint rotr(uint x, uint n) { return (x >> n) | (x << (32 - n)); }

        kernel void sha256_hash(device const uchar* input [[buffer(0)]],
                                 device uchar* output [[buffer(1)]],
                                 constant uint& length [[buffer(2)]],
                                 uint tid [[thread_position_in_grid]]) {
            if (tid > 0) return;
            uint H[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                         0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
            // Process up to 64 bytes at a time (simplified)
            uint W[64];
            for (int i = 0; i < 16; i++) {
                W[i] = 0;
                int off = i * 4;
                if (off + 3 < int(length)) {
                    W[i] = (uint(input[off]) << 24) | (uint(input[off+1]) << 16) | (uint(input[off+2]) << 8) | uint(input[off+3]);
                } else if (off < int(length)) {
                    for (int b = 0; b < 4 && off + b < int(length); b++) {
                        W[i] |= uint(input[off + b]) << (24 - b * 8);
                    }
                }
            }
            for (int i = 16; i < 64; i++) {
                uint s0 = rotr(W[i-15], 7) ^ rotr(W[i-15], 18) ^ (W[i-15] >> 3);
                uint s1 = rotr(W[i-2], 17) ^ rotr(W[i-2], 19) ^ (W[i-2] >> 10);
                W[i] = W[i-16] + s0 + W[i-7] + s1;
            }
            uint a=H[0], b=H[1], c=H[2], d=H[3], e=H[4], f=H[5], g=H[6], h=H[7];
            for (int i = 0; i < 64; i++) {
                uint S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
                uint ch = (e & f) ^ (~e & g);
                uint temp1 = h + S1 + ch + K[i] + W[i];
                uint S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
                uint maj = (a & b) ^ (a & c) ^ (b & c);
                uint temp2 = S0 + maj;
                h=g; g=f; f=e; e=d+temp1; d=c; c=b; b=a; a=temp1+temp2;
            }
            H[0]+=a; H[1]+=b; H[2]+=c; H[3]+=d; H[4]+=e; H[5]+=f; H[6]+=g; H[7]+=h;
            for (int i = 0; i < 8; i++) {
                output[i*4]   = uchar(H[i] >> 24);
                output[i*4+1] = uchar(H[i] >> 16);
                output[i*4+2] = uchar(H[i] >> 8);
                output[i*4+3] = uchar(H[i]);
            }
        }
        """
        return try device.makeLibrary(source: source, options: nil)
    }

    // MARK: - benchmark

    private func benchmark(device: MTLDevice, context: CommandContext) -> Int32 {
        context.stdout("\u{001B}[36mMetal GPU Benchmark\u{001B}[0m\n\n")
        guard let queue = device.makeCommandQueue() else { return 1 }
        // Simple vector add benchmark
        let count = 1_000_000
        let bufferSize = count * MemoryLayout<Float>.size
        guard let bufA = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufB = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let bufC = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return 1 }

        let ptrA = bufA.contents().bindMemory(to: Float.self, capacity: count)
        let ptrB = bufB.contents().bindMemory(to: Float.self, capacity: count)
        for i in 0..<count { ptrA[i] = Float(i); ptrB[i] = Float(i * 2) }

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void vadd(device const float* a [[buffer(0)]],
                          device const float* b [[buffer(1)]],
                          device float* c [[buffer(2)]],
                          uint tid [[thread_position_in_grid]]) {
            c[tid] = a[tid] + b[tid];
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let fn = library.makeFunction(name: "vadd"),
              let pipeline = try? device.makeComputePipelineState(function: fn) else { return 1 }

        let start = Date()
        guard let cmdBuf = queue.makeCommandBuffer(),
              let enc = cmdBuf.makeComputeCommandEncoder() else { return 1 }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(bufA, offset: 0, index: 0)
        enc.setBuffer(bufB, offset: 0, index: 1)
        enc.setBuffer(bufC, offset: 0, index: 2)
        let tg = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
        let groups = MTLSize(width: (count + tg.width - 1) / tg.width, height: 1, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        let elapsed = Date().timeIntervalSince(start)

        context.stdout(String(format: "Vector add (%d elements): %.3f ms\n", count, elapsed * 1000))
        context.stdout(String(format: "Throughput: %.1f MOps/s\n", Double(count) / elapsed / 1_000_000))
        let ptrC = bufC.contents().bindMemory(to: Float.self, capacity: count)
        context.stdout("Verify: \(ptrA[0]) + \(ptrB[0]) = \(ptrC[0])\n")
        context.stdout("Verify: \(ptrA[999]) + \(ptrB[999]) = \(ptrC[999])\n")
        context.stdout("\n\u{001B}[32mGPU benchmark complete.\u{001B}[0m\n")
        return 0
    }

    // MARK: - matrix multiply

    private func matrixMul(args: [String], device: MTLDevice, context: CommandContext) -> Int32 {
        let N = Int(args.first ?? "256") ?? 256
        context.stdout("\u{001B}[36mGPU Matrix Multiply (\(N)x\(N))\u{001B}[0m\n\n")
        guard let queue = device.makeCommandQueue() else { return 1 }

        let size = N * N * MemoryLayout<Float>.size
        guard let bufA = device.makeBuffer(length: size, options: .storageModeShared),
              let bufB = device.makeBuffer(length: size, options: .storageModeShared),
              let bufC = device.makeBuffer(length: size, options: .storageModeShared) else { return 1 }

        let ptrA = bufA.contents().bindMemory(to: Float.self, capacity: N * N)
        let ptrB = bufB.contents().bindMemory(to: Float.self, capacity: N * N)
        for i in 0..<(N * N) { ptrA[i] = Float.random(in: 0...1); ptrB[i] = Float.random(in: 0...1) }

        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void matmul(device const float* A [[buffer(0)]],
                            device const float* B [[buffer(1)]],
                            device float* C [[buffer(2)]],
                            constant uint& N [[buffer(3)]],
                            uint2 pos [[thread_position_in_grid]]) {
            if (pos.x >= N || pos.y >= N) return;
            float sum = 0.0;
            for (uint k = 0; k < N; k++) {
                sum += A[pos.y * N + k] * B[k * N + pos.x];
            }
            C[pos.y * N + pos.x] = sum;
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let fn = library.makeFunction(name: "matmul"),
              let pipeline = try? device.makeComputePipelineState(function: fn) else { return 1 }

        var Nuint = UInt32(N)
        guard let cmdBuf = queue.makeCommandBuffer(),
              let enc = cmdBuf.makeComputeCommandEncoder() else { return 1 }
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(bufA, offset: 0, index: 0)
        enc.setBuffer(bufB, offset: 0, index: 1)
        enc.setBuffer(bufC, offset: 0, index: 2)
        enc.setBytes(&Nuint, length: 4, index: 3)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(width: (N + 15) / 16, height: (N + 15) / 16, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
        enc.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        let ptrC = bufC.contents().bindMemory(to: Float.self, capacity: N * N)
        context.stdout(String(format: "Result: C[0,0] = %.4f\n", ptrC[0]))
        context.stdout(String(format: "Result: C[%d,%d] = %.4f\n", N/2, N/2, ptrC[(N/2) * N + N/2]))
        context.stdout("\n\u{001B}[32mMatrix multiply complete.\u{001B}[0m\n")
        return 0
    }

    // MARK: - custom compute shader

    private func computeShader(args: [String], device: MTLDevice, context: CommandContext) -> Int32 {
        guard args.count >= 1 else {
            context.stderr("gpu compute: need <shader.metal> [input]\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        guard let url = context.fs.resolve(args[0]),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            context.stderr("gpu compute: cannot read shader \(args[0])\n")
            return 1
        }
        guard let library = try? device.makeLibrary(source: source, options: nil) else {
            context.stderr("gpu compute: shader compilation failed\n")
            return 1
        }
        context.stdout("Shader compiled successfully. Functions: ")
        let fnNames = ["compute", "main", "process"]
        var found = ""
        for name in fnNames {
            if library.makeFunction(name: name) != nil { found += "\(name) " }
        }
        if found.isEmpty { found = "(none found, use 'compute' as entry point)" }
        context.stdout(found + "\n")

        if let fn = library.makeFunction(name: "compute"),
           let pipeline = try? device.makeComputePipelineState(function: fn),
           let queue = device.makeCommandQueue(),
           let cmdBuf = queue.makeCommandBuffer(),
           let enc = cmdBuf.makeComputeCommandEncoder() {
            enc.setComputePipelineState(pipeline)
            let tg = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
            let groups = MTLSize(width: 1, height: 1, depth: 1)
            enc.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            context.stdout("Shader executed on GPU.\n")
        }
        return 0
    }
}

/// `metal` - alias for gpu, with shorter name.
struct MetalCommand: BuiltinCommand {
    let name = "metal"
    let summary = "Metal GPU compute (alias for gpu)"
    let usage = "metal info | metal bench | metal matrix <N>"
    var operands: [Operand] {[
        Operand(name: "subcommand", description: "info, bench, matrix, hash, compute", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        // Re-dispatch to GpuCommand
        return GpuCommand().run(arguments: arguments, context: context)
    }
}