import Foundation
import Darwin

enum BenchmarkTestKind: String, CaseIterable, Identifiable, Sendable {
    case sequentialWrite
    case sequentialRead
    case randomWrite
    case randomRead

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .sequentialWrite:
            return 0
        case .sequentialRead:
            return 1
        case .randomWrite:
            return 2
        case .randomRead:
            return 3
        }
    }

    var title: String {
        switch self {
        case .sequentialWrite:
            return "顺序写入"
        case .sequentialRead:
            return "顺序读取"
        case .randomWrite:
            return "随机写入"
        case .randomRead:
            return "随机读取"
        }
    }

    var subtitle: String {
        switch self {
        case .sequentialWrite:
            return "大块连续写入"
        case .sequentialRead:
            return "大块连续读取"
        case .randomWrite:
            return "小块离散写入"
        case .randomRead:
            return "小块离散读取"
        }
    }
}

struct BenchmarkSettings: Sendable {
    let directoryURL: URL
    let fileSizeMB: Int
    let sequentialBlockSizeKB: Int
    let randomBlockSizeKB: Int
    let randomOperationCount: Int

    var fileSizeBytes: Int64 {
        Int64(fileSizeMB) * 1_048_576
    }

    var sequentialBlockSizeBytes: Int {
        sequentialBlockSizeKB * 1_024
    }

    var randomBlockSizeBytes: Int {
        randomBlockSizeKB * 1_024
    }

    var randomAccessBytes: Int64 {
        Int64(randomOperationCount) * Int64(randomBlockSizeBytes)
    }

    var estimatedWriteBytes: Int64 {
        fileSizeBytes + randomAccessBytes
    }

    var estimatedReadBytes: Int64 {
        fileSizeBytes + randomAccessBytes
    }

    var estimatedMovedBytes: Int64 {
        estimatedWriteBytes + estimatedReadBytes
    }
}

struct ProgressSample: Hashable, Sendable {
    let elapsed: TimeInterval
    let value: Double
}

struct BenchmarkProgress: Sendable {
    let activeTest: BenchmarkTestKind
    let completedTests: Int
    let totalTests: Int
    let fractionWithinTest: Double
    let overallFraction: Double
    let liveThroughputMBps: Double
    let processedBytes: Int64
    let totalBytes: Int64
    let samples: [ProgressSample]
}

struct BenchmarkMeasurement: Identifiable, Sendable {
    let kind: BenchmarkTestKind
    let throughputMBps: Double
    let iops: Double
    let latencyMs: Double
    let duration: TimeInterval
    let bytesProcessed: Int64
    let samplePoints: [ProgressSample]

    var id: BenchmarkTestKind { kind }
}

struct BenchmarkRunSummary: Sendable {
    let startedAt: Date
    let finishedAt: Date
    let settings: BenchmarkSettings
    let volume: VolumeInfo
    let measurements: [BenchmarkMeasurement]

    func measurement(for kind: BenchmarkTestKind) -> BenchmarkMeasurement? {
        measurements.first { $0.kind == kind }
    }
}

enum BenchmarkEvent: Sendable {
    case progress(BenchmarkProgress)
    case measurement(BenchmarkMeasurement)
}

enum BenchmarkEngineError: LocalizedError, Sendable {
    case message(String)
    case insufficientSpace(required: Int64, available: Int64?)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        case .insufficientSpace(let required, let available):
            let requiredText = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableText = available.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "未知"
            return "剩余空间不足。至少需要 \(requiredText)，当前可用 \(availableText)。"
        }
    }
}

struct BenchmarkEngine: Sendable {
    typealias EventHandler = @Sendable (BenchmarkEvent) -> Void

    func run(settings: BenchmarkSettings, volume: VolumeInfo, eventHandler: EventHandler) throws -> BenchmarkRunSummary {
        try validate(settings: settings, volume: volume)
        let profile = makeRuntimeProfile(for: settings, volume: volume)

        let benchmarkURL = settings.directoryURL
            .appendingPathComponent(".disktester-\(UUID().uuidString).bin", isDirectory: false)

        let startedAt = Date()
        defer {
            try? FileManager.default.removeItem(at: benchmarkURL)
        }

        var measurements: [BenchmarkMeasurement] = []
        let totalTests = BenchmarkTestKind.allCases.count

        let sequentialWrite = try runSequentialWrite(
            fileURL: benchmarkURL,
            settings: settings,
            profile: profile,
            testIndex: 0,
            totalTests: totalTests,
            eventHandler: eventHandler
        )
        measurements.append(sequentialWrite)
        eventHandler(.measurement(sequentialWrite))

        let sequentialRead = try runSequentialRead(
            fileURL: benchmarkURL,
            settings: settings,
            profile: profile,
            testIndex: 1,
            totalTests: totalTests,
            eventHandler: eventHandler
        )
        measurements.append(sequentialRead)
        eventHandler(.measurement(sequentialRead))

        try prepareFileForRandomAccess(fileURL: benchmarkURL, size: settings.fileSizeBytes)

        let randomWrite = try runRandomWrite(
            fileURL: benchmarkURL,
            settings: settings,
            profile: profile,
            testIndex: 2,
            totalTests: totalTests,
            eventHandler: eventHandler
        )
        measurements.append(randomWrite)
        eventHandler(.measurement(randomWrite))

        let randomRead = try runRandomRead(
            fileURL: benchmarkURL,
            settings: settings,
            profile: profile,
            testIndex: 3,
            totalTests: totalTests,
            eventHandler: eventHandler
        )
        measurements.append(randomRead)
        eventHandler(.measurement(randomRead))

        return BenchmarkRunSummary(
            startedAt: startedAt,
            finishedAt: Date(),
            settings: settings,
            volume: volume,
            measurements: measurements.sorted { $0.kind.sortOrder < $1.kind.sortOrder }
        )
    }

    private func validate(settings: BenchmarkSettings, volume: VolumeInfo) throws {
        if settings.fileSizeBytes <= 0 || settings.sequentialBlockSizeBytes <= 0 || settings.randomBlockSizeBytes <= 0 {
            throw BenchmarkEngineError.message("测试参数无效，请检查文件大小与块大小。")
        }

        let safetyMargin: Int64 = 256 * 1_048_576
        if let available = volume.availableCapacity,
           available < settings.fileSizeBytes + safetyMargin {
            throw BenchmarkEngineError.insufficientSpace(
                required: settings.fileSizeBytes + safetyMargin,
                available: available
            )
        }
    }

    private func runSequentialWrite(
        fileURL: URL,
        settings: BenchmarkSettings,
        profile: BenchmarkRuntimeProfile,
        testIndex: Int,
        totalTests: Int,
        eventHandler: EventHandler
    ) throws -> BenchmarkMeasurement {
        let totalBytes = settings.fileSizeBytes
        let fd = try openFile(at: fileURL, flags: O_CREAT | O_TRUNC | O_RDWR)
        defer { close(fd) }

        applyNoCache(to: fd, enabled: profile.usesDirectIO)
        let buffer = makePatternBuffer(size: profile.sequentialBlockSizeBytes, seed: 0x57)
        var processedBytes: Int64 = 0
        var sampler = ThroughputSampler()

        eventHandler(.progress(makeProgress(
            kind: .sequentialWrite,
            testIndex: testIndex,
            totalTests: totalTests,
            processedBytes: 0,
            totalBytes: totalBytes,
            liveRate: 0,
            samples: []
        )))

        while processedBytes < totalBytes {
            try throwIfCancelled()

            let chunkSize = Int(min(Int64(buffer.count), totalBytes - processedBytes))
            try buffer.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    throw BenchmarkEngineError.message("顺序写入缓冲区初始化失败。")
                }
                try writeAll(fd: fd, from: baseAddress, count: chunkSize)
            }

            processedBytes += Int64(chunkSize)
            let update = sampler.record(processedBytes: processedBytes)
            if update.shouldEmit || processedBytes == totalBytes {
                eventHandler(.progress(makeProgress(
                    kind: .sequentialWrite,
                    testIndex: testIndex,
                    totalTests: totalTests,
                    processedBytes: processedBytes,
                    totalBytes: totalBytes,
                    liveRate: update.rate,
                    samples: sampler.samples
                )))
            }
        }

        sync(fd, useFullSync: profile.usesFullSync)
        let duration = sampler.finish(processedBytes: processedBytes)

        return makeMeasurement(
            kind: .sequentialWrite,
            bytesProcessed: processedBytes,
            ioSize: profile.sequentialBlockSizeBytes,
            duration: duration,
            samples: sampler.samples
        )
    }

    private func runSequentialRead(
        fileURL: URL,
        settings: BenchmarkSettings,
        profile: BenchmarkRuntimeProfile,
        testIndex: Int,
        totalTests: Int,
        eventHandler: EventHandler
    ) throws -> BenchmarkMeasurement {
        let totalBytes = settings.fileSizeBytes
        let fd = try openFile(at: fileURL, flags: O_RDONLY)
        defer { close(fd) }

        applyNoCache(to: fd, enabled: profile.usesDirectIO)
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: profile.sequentialBlockSizeBytes, alignment: 4_096)
        defer { buffer.deallocate() }

        var processedBytes: Int64 = 0
        var sampler = ThroughputSampler()

        eventHandler(.progress(makeProgress(
            kind: .sequentialRead,
            testIndex: testIndex,
            totalTests: totalTests,
            processedBytes: 0,
            totalBytes: totalBytes,
            liveRate: 0,
            samples: []
        )))

        while processedBytes < totalBytes {
            try throwIfCancelled()

            let chunkSize = Int(min(Int64(buffer.count), totalBytes - processedBytes))
            try readFully(fd: fd, into: buffer.baseAddress!, count: chunkSize)
            processedBytes += Int64(chunkSize)

            let update = sampler.record(processedBytes: processedBytes)
            if update.shouldEmit || processedBytes == totalBytes {
                eventHandler(.progress(makeProgress(
                    kind: .sequentialRead,
                    testIndex: testIndex,
                    totalTests: totalTests,
                    processedBytes: processedBytes,
                    totalBytes: totalBytes,
                    liveRate: update.rate,
                    samples: sampler.samples
                )))
            }
        }

        let duration = sampler.finish(processedBytes: processedBytes)

        return makeMeasurement(
            kind: .sequentialRead,
            bytesProcessed: processedBytes,
            ioSize: profile.sequentialBlockSizeBytes,
            duration: duration,
            samples: sampler.samples
        )
    }

    private func runRandomWrite(
        fileURL: URL,
        settings: BenchmarkSettings,
        profile: BenchmarkRuntimeProfile,
        testIndex: Int,
        totalTests: Int,
        eventHandler: EventHandler
    ) throws -> BenchmarkMeasurement {
        let blockSize = profile.randomBlockSizeBytes
        let totalBytes = settings.randomAccessBytes
        let blockCount = max(Int(settings.fileSizeBytes / Int64(blockSize)), 1)
        let operationCount = max(settings.randomOperationCount, 1)

        let fd = try openFile(at: fileURL, flags: O_RDWR)
        defer { close(fd) }

        applyNoCache(to: fd, enabled: profile.usesDirectIO)
        let buffer = makePatternBuffer(size: blockSize, seed: 0xA3)
        var rng = SystemRandomNumberGenerator()
        var processedBytes: Int64 = 0
        var sampler = ThroughputSampler()

        eventHandler(.progress(makeProgress(
            kind: .randomWrite,
            testIndex: testIndex,
            totalTests: totalTests,
            processedBytes: 0,
            totalBytes: totalBytes,
            liveRate: 0,
            samples: []
        )))

        for operationIndex in 0..<operationCount {
            try throwIfCancelled()

            let blockIndex = Int.random(in: 0..<blockCount, using: &rng)
            let offset = Int64(blockIndex * blockSize)

            try buffer.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    throw BenchmarkEngineError.message("随机写入缓冲区初始化失败。")
                }
                try pwriteAll(fd: fd, from: baseAddress, count: blockSize, offset: offset)
            }

            processedBytes += Int64(blockSize)
            let update = sampler.record(processedBytes: processedBytes)
            if update.shouldEmit || operationIndex == operationCount - 1 {
                eventHandler(.progress(makeProgress(
                    kind: .randomWrite,
                    testIndex: testIndex,
                    totalTests: totalTests,
                    processedBytes: processedBytes,
                    totalBytes: totalBytes,
                    liveRate: update.rate,
                    samples: sampler.samples
                )))
            }
        }

        sync(fd, useFullSync: profile.usesFullSync)
        let duration = sampler.finish(processedBytes: processedBytes)

        return makeMeasurement(
            kind: .randomWrite,
            bytesProcessed: processedBytes,
            ioSize: blockSize,
            duration: duration,
            samples: sampler.samples
        )
    }

    private func runRandomRead(
        fileURL: URL,
        settings: BenchmarkSettings,
        profile: BenchmarkRuntimeProfile,
        testIndex: Int,
        totalTests: Int,
        eventHandler: EventHandler
    ) throws -> BenchmarkMeasurement {
        let blockSize = profile.randomBlockSizeBytes
        let totalBytes = settings.randomAccessBytes
        let blockCount = max(Int(settings.fileSizeBytes / Int64(blockSize)), 1)
        let operationCount = max(settings.randomOperationCount, 1)

        let fd = try openFile(at: fileURL, flags: O_RDONLY)
        defer { close(fd) }

        applyNoCache(to: fd, enabled: profile.usesDirectIO)
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: blockSize, alignment: 4_096)
        defer { buffer.deallocate() }

        var rng = SystemRandomNumberGenerator()
        var processedBytes: Int64 = 0
        var sampler = ThroughputSampler()

        eventHandler(.progress(makeProgress(
            kind: .randomRead,
            testIndex: testIndex,
            totalTests: totalTests,
            processedBytes: 0,
            totalBytes: totalBytes,
            liveRate: 0,
            samples: []
        )))

        for operationIndex in 0..<operationCount {
            try throwIfCancelled()

            let blockIndex = Int.random(in: 0..<blockCount, using: &rng)
            let offset = Int64(blockIndex * blockSize)
            try preadFully(fd: fd, into: buffer.baseAddress!, count: blockSize, offset: offset)

            processedBytes += Int64(blockSize)
            let update = sampler.record(processedBytes: processedBytes)
            if update.shouldEmit || operationIndex == operationCount - 1 {
                eventHandler(.progress(makeProgress(
                    kind: .randomRead,
                    testIndex: testIndex,
                    totalTests: totalTests,
                    processedBytes: processedBytes,
                    totalBytes: totalBytes,
                    liveRate: update.rate,
                    samples: sampler.samples
                )))
            }
        }

        let duration = sampler.finish(processedBytes: processedBytes)

        return makeMeasurement(
            kind: .randomRead,
            bytesProcessed: processedBytes,
            ioSize: blockSize,
            duration: duration,
            samples: sampler.samples
        )
    }

    private func makeMeasurement(
        kind: BenchmarkTestKind,
        bytesProcessed: Int64,
        ioSize: Int,
        duration: TimeInterval,
        samples: [ProgressSample]
    ) -> BenchmarkMeasurement {
        let safeDuration = max(duration, 0.000_001)
        let throughput = Double(bytesProcessed) / 1_048_576 / safeDuration
        let operationCount = max(Double(bytesProcessed) / Double(ioSize), 1)
        let iops = operationCount / safeDuration
        let latencyMs = (safeDuration * 1_000) / operationCount

        return BenchmarkMeasurement(
            kind: kind,
            throughputMBps: throughput,
            iops: iops,
            latencyMs: latencyMs,
            duration: safeDuration,
            bytesProcessed: bytesProcessed,
            samplePoints: samples
        )
    }

    private func makeProgress(
        kind: BenchmarkTestKind,
        testIndex: Int,
        totalTests: Int,
        processedBytes: Int64,
        totalBytes: Int64,
        liveRate: Double,
        samples: [ProgressSample]
    ) -> BenchmarkProgress {
        let fractionWithinTest = totalBytes > 0 ? min(max(Double(processedBytes) / Double(totalBytes), 0), 1) : 0
        let overallFraction = min(max((Double(testIndex) + fractionWithinTest) / Double(totalTests), 0), 1)

        return BenchmarkProgress(
            activeTest: kind,
            completedTests: testIndex,
            totalTests: totalTests,
            fractionWithinTest: fractionWithinTest,
            overallFraction: overallFraction,
            liveThroughputMBps: max(liveRate, 0),
            processedBytes: processedBytes,
            totalBytes: totalBytes,
            samples: Array(samples.suffix(120))
        )
    }

    private func prepareFileForRandomAccess(fileURL: URL, size: Int64) throws {
        let fd = try openFile(at: fileURL, flags: O_RDWR | O_CREAT)
        defer { close(fd) }

        if ftruncate(fd, off_t(size)) != 0 {
            throw BenchmarkEngineError.message("初始化随机测试文件失败：\(stringForCurrentErrno()).")
        }
    }

    private func openFile(at url: URL, flags: Int32) throws -> Int32 {
        let mode = mode_t(S_IRUSR | S_IWUSR)
        let fd = url.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else { return Int32(-1) }
            return open(fileSystemPath, flags, mode)
        }

        if fd < 0 {
            throw BenchmarkEngineError.message("打开测试文件失败：\(stringForCurrentErrno()).")
        }

        return fd
    }

    private func writeAll(fd: Int32, from baseAddress: UnsafeRawPointer, count: Int) throws {
        var written = 0
        while written < count {
            let result = Darwin.write(fd, baseAddress.advanced(by: written), count - written)
            if result > 0 {
                written += result
                continue
            }
            if result == -1 && errno == EINTR {
                continue
            }
            throw BenchmarkEngineError.message("写入测试文件失败：\(stringForCurrentErrno()).")
        }
    }

    private func readFully(fd: Int32, into baseAddress: UnsafeMutableRawPointer, count: Int) throws {
        var readBytes = 0
        while readBytes < count {
            let result = Darwin.read(fd, baseAddress.advanced(by: readBytes), count - readBytes)
            if result > 0 {
                readBytes += result
                continue
            }
            if result == 0 {
                throw BenchmarkEngineError.message("读取测试文件时提前到达 EOF。")
            }
            if errno == EINTR {
                continue
            }
            throw BenchmarkEngineError.message("读取测试文件失败：\(stringForCurrentErrno()).")
        }
    }

    private func pwriteAll(fd: Int32, from baseAddress: UnsafeRawPointer, count: Int, offset: Int64) throws {
        var written = 0
        while written < count {
            let result = Darwin.pwrite(fd, baseAddress.advanced(by: written), count - written, off_t(offset + Int64(written)))
            if result > 0 {
                written += result
                continue
            }
            if result == -1 && errno == EINTR {
                continue
            }
            throw BenchmarkEngineError.message("随机写入失败：\(stringForCurrentErrno()).")
        }
    }

    private func preadFully(fd: Int32, into baseAddress: UnsafeMutableRawPointer, count: Int, offset: Int64) throws {
        var readBytes = 0
        while readBytes < count {
            let result = Darwin.pread(fd, baseAddress.advanced(by: readBytes), count - readBytes, off_t(offset + Int64(readBytes)))
            if result > 0 {
                readBytes += result
                continue
            }
            if result == 0 {
                throw BenchmarkEngineError.message("随机读取时提前到达 EOF。")
            }
            if errno == EINTR {
                continue
            }
            throw BenchmarkEngineError.message("随机读取失败：\(stringForCurrentErrno()).")
        }
    }

    private func applyNoCache(to fd: Int32, enabled: Bool) {
        guard enabled else { return }
        _ = fcntl(fd, F_NOCACHE, 1)
    }

    private func sync(_ fd: Int32, useFullSync: Bool) {
        if useFullSync {
            _ = fcntl(fd, F_FULLFSYNC)
        }
        _ = fsync(fd)
    }

    private func makePatternBuffer(size: Int, seed: UInt8) -> Data {
        var data = Data(count: size)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            var rollingValue = seed
            for index in 0..<size {
                rollingValue &+= 31
                rollingValue ^= UInt8(truncatingIfNeeded: index &* 17)
                baseAddress[index] = rollingValue
            }
        }
        return data
    }

    private func stringForCurrentErrno() -> String {
        String(cString: strerror(errno))
    }

    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private func makeRuntimeProfile(for settings: BenchmarkSettings, volume: VolumeInfo) -> BenchmarkRuntimeProfile {
        if volume.isNetworkVolume {
            return BenchmarkRuntimeProfile(
                sequentialBlockSizeBytes: max(settings.sequentialBlockSizeBytes, 4 * 1_024 * 1_024),
                randomBlockSizeBytes: settings.randomBlockSizeBytes,
                usesDirectIO: false,
                usesFullSync: false
            )
        }

        return BenchmarkRuntimeProfile(
            sequentialBlockSizeBytes: settings.sequentialBlockSizeBytes,
            randomBlockSizeBytes: settings.randomBlockSizeBytes,
            usesDirectIO: true,
            usesFullSync: true
        )
    }
}

private struct BenchmarkRuntimeProfile {
    let sequentialBlockSizeBytes: Int
    let randomBlockSizeBytes: Int
    let usesDirectIO: Bool
    let usesFullSync: Bool
}

private struct ThroughputSampler {
    private let startTime: TimeInterval
    private var lastSampleTime: TimeInterval
    private var lastSampleBytes: Int64
    private let interval: TimeInterval = 0.12

    private(set) var samples: [ProgressSample]

    init() {
        let now = ProcessInfo.processInfo.systemUptime
        startTime = now
        lastSampleTime = now
        lastSampleBytes = 0
        samples = []
    }

    mutating func record(processedBytes: Int64) -> (rate: Double, shouldEmit: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = max(now - lastSampleTime, 0.000_001)
        let deltaBytes = processedBytes - lastSampleBytes
        let rate = max(Double(deltaBytes) / 1_048_576 / deltaTime, 0)

        if now - lastSampleTime >= interval {
            samples.append(ProgressSample(elapsed: now - startTime, value: rate))
            lastSampleTime = now
            lastSampleBytes = processedBytes
            return (rate, true)
        }

        return (rate, false)
    }

    mutating func finish(processedBytes: Int64) -> TimeInterval {
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = max(now - lastSampleTime, 0.000_001)
        let deltaBytes = processedBytes - lastSampleBytes
        let rate = max(Double(deltaBytes) / 1_048_576 / deltaTime, 0)
        let elapsed = max(now - startTime, 0.000_001)

        samples.append(ProgressSample(elapsed: elapsed, value: rate))
        lastSampleTime = now
        lastSampleBytes = processedBytes

        return elapsed
    }
}
