import AppKit
import Metal

/// Offscreen checks exercise the shipped Metal entry point and Swift uniform layout.
/// No screen capture, permissions, or simulated hardware readings are involved.
enum IntegrationCheck {
    static func run(output: String) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw failure("Metal unavailable")
        }
        let url = Bundle.main.resourceURL!.appendingPathComponent("FoldShaders.metal")
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "foldVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "foldFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        let sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
        let width = 640, height = 400
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = .shaderRead
        let input = device.makeTexture(descriptor: inputDescriptor)!
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let grid = x % 80 < 3 || y % 50 < 3
                pixels[i] = grid ? 255 : UInt8(40 + x * 160 / width)
                pixels[i + 1] = grid ? 255 : UInt8(40 + y * 160 / height)
                pixels[i + 2] = grid ? 255 : 130
            }
        }
        pixels.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func render(turn: Float, blur: Float, mode: Float = 1, save: String? = nil) throws -> [UInt8] {
            let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
            targetDescriptor.storageMode = .shared
            targetDescriptor.usage = .renderTarget
            let target = device.makeTexture(descriptor: targetDescriptor)!
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            var uniforms = Uniforms(imageSize: .init(Float(width), Float(height)), aspect: Float(width) / Float(height), turn: turn, blurStrength: blur, reflectionIntensity: 0)
            uniforms.effectMode = mode
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(input, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            var result = [UInt8](repeating: 0, count: pixels.count)
            result.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
            if let save {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
                result.withUnsafeBytes { bitmap.bitmapData!.update(from: $0.bindMemory(to: UInt8.self).baseAddress!, count: result.count) }
                try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(save))
            }
            return result
        }

        let opened = try render(turn: 0, blur: 0.5, save: "01-open.png")
        let maxError = zip(opened, pixels).map { abs(Int($0) - Int($1)) }.max()!
        guard maxError <= 1 else { throw failure("Open frame does not match source: \(maxError)") }
        let half = try render(turn: 0.5, blur: 0.5, save: "03-half.png")
        _ = try render(turn: 0.25, blur: 0.5, save: "02-quarter.png")
        _ = try render(turn: 0.75, blur: 0.5, save: "04-deep.png")
        let closed = try render(turn: 1, blur: 0.5, save: "05-closed.png")
        for i in stride(from: 0, to: closed.count, by: 4) {
            let black = closed[i] == 0 && closed[i + 1] == 0 && closed[i + 2] == 0
            guard black, closed[i + 3] == 255 else {
                throw failure("Closed frame is not opaque black")
            }
        }
        guard half != opened, half != closed else { throw failure("Mid-fold frame is missing") }
        let sharp = try render(turn: 0.5, blur: 0, save: "06-projection-no-blur.png")
        guard sharp != half else { throw failure("Blur parameter is not connected") }
        let legacy = try render(turn: 0.5, blur: 0, mode: 0)
        guard legacy != sharp else { throw failure("Original/Duo switch is not connected") }

        // Independent ray-plane reference at interior, non-grid points; verifies
        // that bottom-hinge orientation and aspect survive the Swift/Metal bridge.
        let theta = Double(Float(1.954769)) * 0.5
        var checked = 0
        for y in stride(from: 29, to: height, by: 43) {
            for x in stride(from: 31, to: width, by: 61) {
                let u = (Double(x) + 0.5) / Double(width)
                let v = (Double(y) + 0.5) / Double(height)
                let gap = (1 - v) * sin(theta)
                let t = 2.5 / (2.5 - gap)
                let hitX = (0.5 + (u - 0.5) * t) * Double(width) - 0.5
                let hitY = (0.5 + (0.5 - (1 - v) * cos(theta)) * t) * Double(height) - 0.5
                guard hitX > 4, hitX < Double(width - 4), hitY > 4, hitY < Double(height - 4),
                      Int(hitX) % 80 > 5, Int(hitX) % 80 < 77,
                      Int(hitY) % 50 > 5, Int(hitY) % 50 < 47 else { continue }
                let i = (y * width + x) * 4
                let r = 40 + hitX * 160 / Double(width)
                let g = 40 + hitY * 160 / Double(height)
                guard abs(Double(sharp[i]) - r) < 3, abs(Double(sharp[i + 1]) - g) < 3 else {
                    throw failure("Projection reference mismatch at \(x),\(y)")
                }
                checked += 1
            }
        }
        guard checked > 10 else { throw failure("Insufficient reference samples") }
        // Scrubbing backward must yield the same angle-driven frame.
        let reversed = try render(turn: 0.5, blur: 0.5)
        guard reversed == half else { throw failure("Reverse scrub changed a fixed-angle frame") }
        print("PASS: runtime Metal compilation; open identity (max error \(maxError)); \(checked) CPU projection references; blur; mode switch; black closure; reversible rendering. GPU: \(device.name).")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "IntegrationCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
