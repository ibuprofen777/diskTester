import Foundation

enum PerformanceInsights {
    static func makeLines(from summary: BenchmarkRunSummary?) -> [String] {
        guard let summary else {
            return [
                "这块区域会在测速完成后给出更贴近真实工作流的解读，例如大文件拷贝、素材盘和小文件工程表现。",
                "当前 MVP 已经支持顺序读写、随机读写、实时曲线和卷信息识别。",
                "如果你后续想继续扩展，下一步很适合加入持续写入掉速测试、结果历史和 CSV/JSON 导出。"
            ]
        }

        var lines: [String] = []

        if let sequentialRead = summary.measurement(for: .sequentialRead),
           let sequentialWrite = summary.measurement(for: .sequentialWrite) {
            let floorValue = min(sequentialRead.throughputMBps, sequentialWrite.throughputMBps)
            switch floorValue {
            case 2_000...:
                lines.append("顺序读写都非常强，更适合作为高速 NVMe 素材盘、缓存盘或大型工程构建盘。")
            case 900..<2_000:
                lines.append("顺序吞吐已经足够覆盖大多数外置 SSD、4K 素材拷贝和常见开发缓存场景。")
            case 300..<900:
                lines.append("顺序吞吐更接近中端 SATA SSD 或较好的 USB 移动盘，适合日常拷贝和轻量素材工作流。")
            default:
                lines.append("顺序吞吐偏保守，更像机械盘、U 盘或受接口限制的设备，建议重点关注连接协议和线材。")
            }
        }

        if let randomRead = summary.measurement(for: .randomRead),
           let randomWrite = summary.measurement(for: .randomWrite) {
            let randomScore = min(randomRead.iops, randomWrite.iops)
            switch randomScore {
            case 80_000...:
                lines.append("随机访问能力很扎实，小文件工程、依赖安装、索引构建和应用启动会更顺滑。")
            case 20_000..<80_000:
                lines.append("随机访问表现中上，日常开发目录、照片库和常规 App 数据读写都能稳定胜任。")
            default:
                lines.append("随机访问偏弱，批量小文件或高并发目录扫描时更容易感到拖沓。")
            }
        }

        if let randomWrite = summary.measurement(for: .randomWrite) {
            if randomWrite.latencyMs < 0.2 {
                lines.append("随机写入延迟很低，交互型工作负载会更接近“秒开”和“秒响应”的体感。")
            } else if randomWrite.latencyMs > 2 {
                lines.append("随机写入延迟偏高，说明这块盘更适合顺序大文件，不太适合密集小文件写入。")
            }
        }

        lines.append("当前测试基于 \(summary.settings.fileSizeMB) MB 测试文件、\(summary.settings.sequentialBlockSizeKB) KB 顺序块和 \(summary.settings.randomBlockSizeKB) KB 随机块。")

        return Array(lines.prefix(4))
    }
}
