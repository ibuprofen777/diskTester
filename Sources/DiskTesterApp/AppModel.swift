import SwiftUI
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedDirectoryURL: URL?
    @Published var volumeInfo: VolumeInfo?
    @Published var fileSizeMB: Int = 1_024
    @Published var sequentialBlockSizeKB: Int = 1_024
    @Published var randomBlockSizeKB: Int = 4
    @Published var randomOperationCount: Int = 25_000
    @Published var isRunning = false
    @Published var progress: BenchmarkProgress?
    @Published var measurements: [BenchmarkMeasurement] = []
    @Published var currentRun: BenchmarkRunSummary?
    @Published var errorMessage: String?
    @Published var statusMessage = "选择一个目录后即可开始测试。"

    private var benchmarkTask: Task<Void, Never>?
    private var engineTask: Task<BenchmarkRunSummary, Error>?
    private var activeRunToken = UUID()

    let fileSizeOptions = [512, 1_024, 2_048, 4_096, 8_192]
    let sequentialBlockSizeOptions = [256, 512, 1_024, 2_048]
    let randomBlockSizeOptions = [4, 16, 64, 128]
    let randomOperationOptions = [10_000, 25_000, 50_000, 80_000]

    init() {
        selectedDirectoryURL = defaultDirectory()
        refreshVolumeInfo()
    }

    deinit {
        benchmarkTask?.cancel()
        engineTask?.cancel()
    }

    var selectedDirectoryPath: String {
        selectedDirectoryURL?.path(percentEncoded: false) ?? "未选择目录"
    }

    var canStart: Bool {
        selectedDirectoryURL != nil && !isRunning
    }

    var estimatedWriteText: String {
        ByteCountFormatter.string(fromByteCount: currentSettings.estimatedWriteBytes, countStyle: .file)
    }

    var estimatedMovedText: String {
        ByteCountFormatter.string(fromByteCount: currentSettings.estimatedMovedBytes, countStyle: .file)
    }

    var currentSettings: BenchmarkSettings {
        BenchmarkSettings(
            directoryURL: selectedDirectoryURL ?? defaultDirectory(),
            fileSizeMB: fileSizeMB,
            sequentialBlockSizeKB: sequentialBlockSizeKB,
            randomBlockSizeKB: randomBlockSizeKB,
            randomOperationCount: randomOperationCount
        )
    }

    var chartSamples: [ProgressSample] {
        if let progress {
            return progress.samples
        }
        if let lastMeasurement = measurements.sorted(by: { $0.kind.sortOrder < $1.kind.sortOrder }).last {
            return lastMeasurement.samplePoints
        }
        return []
    }

    var chartTitle: String {
        if let progress {
            return "\(progress.activeTest.title) 实时曲线"
        }
        if let lastMeasurement = measurements.sorted(by: { $0.kind.sortOrder < $1.kind.sortOrder }).last {
            return "\(lastMeasurement.kind.title) 结果曲线"
        }
        return "等待测速开始"
    }

    var insightLines: [String] {
        PerformanceInsights.makeLines(from: currentRun)
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择测试目录"
        panel.message = "DiskTester 会在这里创建临时测试文件，完成后自动删除。"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = selectedDirectoryURL

        if panel.runModal() == .OK, let directory = panel.url {
            selectedDirectoryURL = directory
            refreshVolumeInfo()
            statusMessage = "已选择 \(directory.lastPathComponent)，可以开始测试。"
        }
    }

    func startBenchmark() {
        guard !isRunning else { return }
        guard let directory = selectedDirectoryURL else {
            errorMessage = "请先选择一个可写的测试目录。"
            return
        }

        do {
            let volume = try SystemInspector.volumeInfo(for: directory)
            volumeInfo = volume
            let settings = currentSettings

            isRunning = true
            progress = nil
            measurements = []
            currentRun = nil
            errorMessage = nil
            statusMessage = "准备测试 \(volume.volumeName)..."
            let runToken = UUID()
            activeRunToken = runToken

            let engineTask = Task.detached(priority: .userInitiated) { [settings, volume] in
                let engine = BenchmarkEngine()
                return try engine.run(settings: settings, volume: volume) { event in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeRunToken == runToken else { return }
                        switch event {
                        case .progress(let snapshot):
                            self.progress = snapshot
                            self.statusMessage = "正在执行 \(snapshot.activeTest.title) \(Self.percentText(snapshot.overallFraction))"
                        case .measurement(let measurement):
                            self.upsert(measurement: measurement)
                        }
                    }
                }
            }
            self.engineTask = engineTask

            benchmarkTask = Task { [weak self] in
                guard let self else { return }

                do {
                    let summary = try await engineTask.value
                    if activeRunToken == runToken {
                        currentRun = summary
                        measurements = summary.measurements
                        progress = nil
                        statusMessage = "测试完成，总耗时 \(Self.durationText(summary.finishedAt.timeIntervalSince(summary.startedAt)))。"
                    }
                } catch is CancellationError {
                    if activeRunToken == runToken {
                        progress = nil
                        statusMessage = "测试已停止。"
                    }
                } catch {
                    if activeRunToken == runToken {
                        progress = nil
                        errorMessage = error.localizedDescription
                        statusMessage = "测试失败，请调整参数后重试。"
                    }
                }

                if activeRunToken == runToken {
                    isRunning = false
                }
                self.engineTask = nil
                benchmarkTask = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopBenchmark() {
        activeRunToken = UUID()
        engineTask?.cancel()
        benchmarkTask?.cancel()
        engineTask = nil
        benchmarkTask = nil
        progress = nil
        isRunning = false
        statusMessage = "正在停止测试..."
    }

    func measurement(for kind: BenchmarkTestKind) -> BenchmarkMeasurement? {
        measurements.first { $0.kind == kind }
    }

    func activeProgress(for kind: BenchmarkTestKind) -> BenchmarkProgress? {
        guard progress?.activeTest == kind else { return nil }
        return progress
    }

    private func refreshVolumeInfo() {
        guard let selectedDirectoryURL else {
            volumeInfo = nil
            return
        }

        volumeInfo = try? SystemInspector.volumeInfo(for: selectedDirectoryURL)
    }

    private func upsert(measurement: BenchmarkMeasurement) {
        if let index = measurements.firstIndex(where: { $0.kind == measurement.kind }) {
            measurements[index] = measurement
        } else {
            measurements.append(measurement)
        }
        measurements.sort { $0.kind.sortOrder < $1.kind.sortOrder }
    }

    private func defaultDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        if FileManager.default.fileExists(atPath: downloads.path(percentEncoded: false)) {
            return downloads
        }
        return home
    }

    static func speedText(_ value: Double) -> String {
        if value >= 1_000 {
            return String(format: "%.0f MB/s", value)
        }
        return String(format: "%.1f MB/s", value)
    }

    static func iopsText(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    static func latencyText(_ value: Double) -> String {
        if value < 1 {
            return String(format: "%.3f ms", value)
        }
        if value < 10 {
            return String(format: "%.2f ms", value)
        }
        return String(format: "%.1f ms", value)
    }

    static func percentText(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    static func durationText(_ value: TimeInterval) -> String {
        if value < 1 {
            return String(format: "%.0f ms", value * 1_000)
        }
        if value < 60 {
            return String(format: "%.1f s", value)
        }
        let minutes = Int(value) / 60
        let seconds = Int(value) % 60
        return "\(minutes)m \(seconds)s"
    }
}
