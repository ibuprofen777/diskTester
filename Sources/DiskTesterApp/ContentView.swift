import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = width < 1_180
            let sidebarWidth = min(max(width * 0.28, 320), 380)
            let mainContentWidth = max(isCompact ? width - 48 : width - sidebarWidth - 92, 320)

            ZStack {
                background

                ScrollView {
                    VStack(spacing: 22) {
                        heroPanel(isCompact: isCompact)
                        overviewStrip

                        if isCompact {
                            VStack(spacing: 18) {
                                resultsSection(availableWidth: mainContentWidth)
                                trendPanel
                                insightPanel
                                targetPanel
                                controlsPanel
                                liveStatusPanel
                            }
                        } else {
                            HStack(alignment: .top, spacing: 22) {
                                VStack(spacing: 18) {
                                    targetPanel
                                    controlsPanel
                                    liveStatusPanel
                                }
                                .frame(width: sidebarWidth)

                                VStack(spacing: 18) {
                                    resultsSection(availableWidth: mainContentWidth)
                                    trendPanel
                                    insightPanel
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1_520)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .alert(
            "测试异常",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.93, blue: 0.88),
                Color(red: 0.88, green: 0.93, blue: 0.90),
                Color(red: 0.78, green: 0.84, blue: 0.84)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 420)
                .blur(radius: 14)
                .offset(x: 420, y: -240)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 180)
                .fill(Color(red: 0.14, green: 0.31, blue: 0.31).opacity(0.08))
                .frame(width: 520, height: 260)
                .rotationEffect(.degrees(-18))
                .offset(x: -360, y: 260)
        )
        .ignoresSafeArea()
    }

    private func heroPanel(isCompact: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.20, blue: 0.21),
                            Color(red: 0.18, green: 0.36, blue: 0.34),
                            Color(red: 0.72, green: 0.39, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 4)
                .offset(x: 420, y: -110)

            RoundedRectangle(cornerRadius: 60, style: .continuous)
                .fill(Color.black.opacity(0.08))
                .frame(width: 320, height: 120)
                .rotationEffect(.degrees(-12))
                .offset(x: -70, y: 80)

            Group {
                if isCompact {
                    VStack(alignment: .leading, spacing: 18) {
                        heroCopy
                        heroStatus
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 24) {
                        heroCopy
                        Spacer(minLength: 20)
                        VStack(alignment: .trailing, spacing: 14) {
                            heroStatus
                        }
                        .frame(maxWidth: 420, alignment: .trailing)
                    }
                }
            }
            .padding(28)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 26, y: 12)
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DiskTester")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)

            Text("macOS 原生磁盘测速工作台")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))

            Text("顺序 / 随机读写、卷信息、实时曲线和协议识别都集中到一个更清晰的仪表盘里。")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(selectedVolumeHeadline)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)

                Text(selectedVolumeCaption)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
        }
    }

    private var heroStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.statusMessage)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.14)))

            if let progress = model.progress {
                HStack(spacing: 12) {
                    ProgressView(value: progress.overallFraction)
                        .frame(minWidth: 180)
                        .tint(Color.white)

                    Text(AppModel.percentText(progress.overallFraction))
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
            } else if let bestMeasurement {
                HStack(spacing: 12) {
                    HeroMetric(label: "最高吞吐", value: AppModel.speedText(bestMeasurement.throughputMBps))
                    HeroMetric(label: "最佳阶段", value: bestMeasurement.kind.title)
                }
            }
        }
    }

    private var overviewStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
            OverviewTile(
                icon: "internaldrive.fill",
                title: "当前目标",
                value: model.volumeInfo?.volumeName ?? "未选择卷",
                detail: [fileSystemText, model.volumeInfo?.connectionProtocol].compactMap { $0 }.joined(separator: "  ·  "),
                tint: Color(red: 0.14, green: 0.47, blue: 0.43)
            )
            OverviewTile(
                icon: "externaldrive.fill.badge.checkmark",
                title: "可用容量",
                value: readableBytes(model.volumeInfo?.availableCapacity),
                detail: "总容量 \(readableBytes(model.volumeInfo?.totalCapacity))",
                tint: Color(red: 0.23, green: 0.35, blue: 0.67)
            )
            OverviewTile(
                icon: "arrow.left.arrow.right.square.fill",
                title: "预计写入",
                value: model.estimatedWriteText,
                detail: "总数据量 \(model.estimatedMovedText)",
                tint: Color(red: 0.74, green: 0.35, blue: 0.22)
            )
            OverviewTile(
                icon: "bolt.horizontal.circle.fill",
                title: "运行状态",
                value: statusOverviewTitle,
                detail: statusOverviewDetail,
                tint: Color(red: 0.56, green: 0.42, blue: 0.14)
            )
        }
    }

    private func resultsSection(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLead(
                title: "核心结果",
                subtitle: "把四项核心测试放在最前面，方便横向比较顺序与随机性能。"
            )

            LazyVGrid(columns: resultColumns(for: availableWidth), spacing: 18) {
                ForEach(BenchmarkTestKind.allCases) { kind in
                    ResultCard(
                        kind: kind,
                        measurement: model.measurement(for: kind),
                        progress: model.activeProgress(for: kind)
                    )
                }
            }
        }
    }

    private var targetPanel: some View {
        Panel(title: "测试工作台", subtitle: "把选择目录、参数设置和开始测速收在一起") {
            VStack(alignment: .leading, spacing: 16) {
                ValueBlock(
                    label: "测试目录",
                    value: model.selectedDirectoryPath,
                    icon: "folder.fill"
                )

                HStack(spacing: 12) {
                    Button("选择目录") {
                        model.chooseDirectory()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.14, green: 0.38, blue: 0.36))

                    Button("开始测速") {
                        model.startBenchmark()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.80, green: 0.36, blue: 0.21))
                    .disabled(!model.canStart)

                    Button("停止") {
                        model.stopBenchmark()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.isRunning)
                }

                Divider()

                SectionLead(
                    title: "测试参数",
                    subtitle: "先选目录，再调参数，然后直接开始。"
                )

                ParameterPickerRow(
                    title: "测试文件大小",
                    selection: $model.fileSizeMB,
                    values: model.fileSizeOptions,
                    valueText: { "\($0) MB" },
                    hint: "越大越能降低缓存干扰"
                )

                ParameterPickerRow(
                    title: "顺序块大小",
                    selection: $model.sequentialBlockSizeKB,
                    values: model.sequentialBlockSizeOptions,
                    valueText: { "\($0) KB" },
                    hint: "适合大文件吞吐测试"
                )

                ParameterPickerRow(
                    title: "随机块大小",
                    selection: $model.randomBlockSizeKB,
                    values: model.randomBlockSizeOptions,
                    valueText: { "\($0) KB" },
                    hint: "适合小文件与离散访问"
                )

                ParameterPickerRow(
                    title: "随机操作次数",
                    selection: $model.randomOperationCount,
                    values: model.randomOperationOptions,
                    valueText: { "\($0.formatted(.number.grouping(.never))) 次" },
                    hint: "次数越多，随机结果越稳定"
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    InfoTile(label: "预计写入", value: model.estimatedWriteText)
                    InfoTile(label: "总数据量", value: model.estimatedMovedText)
                }

                NoticeCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "写入提醒",
                    message: "测试会在所选目录写入临时文件，结束后自动删除。建议避开系统盘高负载时段，并确保外置盘已稳定挂载。"
                )
            }
        }
    }

    private var controlsPanel: some View {
        Panel(title: "卷详情", subtitle: "作为当前测试结果的上下文信息") {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    InfoTile(label: "卷名", value: model.volumeInfo?.volumeName ?? "未识别")
                    InfoTile(label: "文件系统", value: fileSystemText)
                    InfoTile(label: "连接协议", value: model.volumeInfo?.connectionProtocol ?? "未识别")
                    InfoTile(label: "可用容量", value: readableBytes(model.volumeInfo?.availableCapacity))
                    InfoTile(label: "总容量", value: readableBytes(model.volumeInfo?.totalCapacity))
                    InfoTile(label: "介质属性", value: volumeTraits)
                }

                ValueBlock(
                    label: "挂载点",
                    value: model.volumeInfo?.mountPoint ?? "未识别",
                    icon: "point.3.connected.trianglepath.dotted"
                )
            }
        }
    }

    private var liveStatusPanel: some View {
        Panel(title: "当前阶段", subtitle: "实时状态与吞吐反馈") {
            VStack(alignment: .leading, spacing: 16) {
                if let progress = model.progress {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        StatusTile(label: "阶段", value: progress.activeTest.title)
                        StatusTile(label: "阶段进度", value: AppModel.percentText(progress.fractionWithinTest))
                        StatusTile(label: "实时速度", value: AppModel.speedText(progress.liveThroughputMBps))
                        StatusTile(label: "已处理", value: readableBytes(progress.processedBytes))
                        StatusTile(label: "目标量", value: readableBytes(progress.totalBytes))
                    }
                } else if let latest = model.measurements.last {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        StatusTile(label: "最近完成", value: latest.kind.title)
                        StatusTile(label: "峰值显示", value: AppModel.speedText(latest.throughputMBps))
                        StatusTile(label: "IOPS", value: AppModel.iopsText(latest.iops))
                        StatusTile(label: "延迟", value: AppModel.latencyText(latest.latencyMs))
                    }
                } else {
                    Text("选择目录并点击“开始测速”后，这里会展示当前阶段、实时吞吐和进度。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var trendPanel: some View {
        Panel(title: "速度曲线", subtitle: model.chartTitle) {
            VStack(alignment: .leading, spacing: 16) {
                SparklineView(samples: model.chartSamples)
                    .frame(height: 220)

                if let progress = model.progress {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            StatChip(label: "实时速度", value: AppModel.speedText(progress.liveThroughputMBps))
                            StatChip(label: "当前阶段", value: progress.activeTest.title)
                            StatChip(label: "总体进度", value: AppModel.percentText(progress.overallFraction))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            StatChip(label: "实时速度", value: AppModel.speedText(progress.liveThroughputMBps))
                            StatChip(label: "当前阶段", value: progress.activeTest.title)
                            StatChip(label: "总体进度", value: AppModel.percentText(progress.overallFraction))
                        }
                    }
                } else if let best = bestMeasurement {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            StatChip(label: "最高吞吐", value: AppModel.speedText(best.throughputMBps))
                            StatChip(label: "来自阶段", value: best.kind.title)
                            StatChip(label: "耗时", value: AppModel.durationText(best.duration))
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            StatChip(label: "最高吞吐", value: AppModel.speedText(best.throughputMBps))
                            StatChip(label: "来自阶段", value: best.kind.title)
                            StatChip(label: "耗时", value: AppModel.durationText(best.duration))
                        }
                    }
                } else {
                    Text("测速开始后会在这里绘制 MB/s 变化曲线，方便观察掉速、波动和收尾稳定性。")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
        }
    }

    private var insightPanel: some View {
        Panel(title: "结果解读", subtitle: "让数字更接近真实场景") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(model.insightLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.78, green: 0.34, blue: 0.19))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)

                        Text(line)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var volumeTraits: String {
        guard let volume = model.volumeInfo else {
            return "未识别"
        }

        var parts: [String] = []
        if volume.isNetworkVolume { parts.append("网络卷") }
        if volume.isInternal == true { parts.append("内置") }
        if volume.isRemovable == true { parts.append("可移除") }
        if volume.isEjectable == true { parts.append("可弹出") }
        if parts.isEmpty { parts.append("本地卷") }
        return parts.joined(separator: " / ")
    }

    private var fileSystemText: String {
        guard let volume = model.volumeInfo else {
            return "未识别"
        }

        let normalizedType = volume.fileSystemName.uppercased()
        let normalizedDescription = volume.formatDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedDescription.caseInsensitiveCompare(normalizedType) == .orderedSame {
            return normalizedDescription
        }

        return "\(normalizedDescription) (\(normalizedType))"
    }

    private var selectedVolumeHeadline: String {
        model.volumeInfo?.volumeName ?? "还没有选择测试卷"
    }

    private var selectedVolumeCaption: String {
        guard let volume = model.volumeInfo else {
            return "先选择一个目录，系统会自动识别卷、文件系统、协议和剩余容量。"
        }

        return [
            fileSystemText,
            volume.connectionProtocol ?? "协议未识别",
            "可用 \(readableBytes(volume.availableCapacity))"
        ].joined(separator: "  ·  ")
    }

    private var bestMeasurement: BenchmarkMeasurement? {
        model.measurements.max(by: { $0.throughputMBps < $1.throughputMBps })
    }

    private var statusOverviewTitle: String {
        if let progress = model.progress {
            return progress.activeTest.title
        }
        if let bestMeasurement {
            return AppModel.speedText(bestMeasurement.throughputMBps)
        }
        return model.isRunning ? "准备中" : "待机"
    }

    private var statusOverviewDetail: String {
        if let progress = model.progress {
            return "总体进度 \(AppModel.percentText(progress.overallFraction))"
        }
        if let bestMeasurement {
            return "当前最佳来自 \(bestMeasurement.kind.title)"
        }
        return "选择目录后即可开始测试"
    }

    private func resultColumns(for availableWidth: CGFloat) -> [GridItem] {
        let minimum: CGFloat = availableWidth > 1_020 ? 215 : 240
        let count = max(1, min(4, Int((availableWidth + 18) / (minimum + 18))))
        return Array(repeating: GridItem(.flexible(minimum: minimum), spacing: 18), count: count)
    }

    private func readableBytes(_ value: Int64?) -> String {
        guard let value else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

private struct Panel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.11, green: 0.20, blue: 0.21))

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.54))
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 18, y: 8)
    }
}

private struct SectionLead: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.20, blue: 0.21))

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.50))
        }
    }
}

private struct HeroMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))

            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
    }
}

private struct OverviewTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.50))

            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.78))
                .lineLimit(2)

            Text(detail.isEmpty ? " " : detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.54))
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.76))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
    }
}

private struct ValueBlock: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.14, green: 0.29, blue: 0.29))

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.72))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

private struct InfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.46))

            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.74))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

private struct ParameterPickerRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let values: [Value]
    let valueText: (Value) -> String
    let hint: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))

                Text(hint)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.48))
            }

            Spacer(minLength: 12)

            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { value in
                    Text(valueText(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 150)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.86))
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

private struct NoticeCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 0.80, green: 0.36, blue: 0.21))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.72))

                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.98, green: 0.93, blue: 0.88))
        )
    }
}

private struct StatusTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.48))

            Text(value)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.74))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }
}

private struct ResultCard: View {
    let kind: BenchmarkTestKind
    let measurement: BenchmarkMeasurement?
    let progress: BenchmarkProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)

                    Text(kind.subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.74))
                }

                Spacer()

                if progress != nil {
                    Text("进行中")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.22)))
                        .foregroundStyle(Color.white)
                }
            }

            if let measurement {
                Text(AppModel.speedText(measurement.throughputMBps))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        MetricPill(label: "IOPS", value: AppModel.iopsText(measurement.iops))
                        MetricPill(label: "延迟", value: AppModel.latencyText(measurement.latencyMs))
                        MetricPill(label: "耗时", value: AppModel.durationText(measurement.duration))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        MetricPill(label: "IOPS", value: AppModel.iopsText(measurement.iops))
                        MetricPill(label: "延迟", value: AppModel.latencyText(measurement.latencyMs))
                        MetricPill(label: "耗时", value: AppModel.durationText(measurement.duration))
                    }
                }
            } else if let progress {
                Text(AppModel.speedText(progress.liveThroughputMBps))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        MetricPill(label: "阶段进度", value: AppModel.percentText(progress.fractionWithinTest))
                        MetricPill(label: "已处理", value: ByteCountFormatter.string(fromByteCount: progress.processedBytes, countStyle: .file))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        MetricPill(label: "阶段进度", value: AppModel.percentText(progress.fractionWithinTest))
                        MetricPill(label: "已处理", value: ByteCountFormatter.string(fromByteCount: progress.processedBytes, countStyle: .file))
                    }
                }
            } else {
                Text("等待测试")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text("开始后会在这里显示吞吐、IOPS 和平均延迟。")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(gradient(for: kind))
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 120, height: 120)
                        .blur(radius: 6)
                        .offset(x: 24, y: -24)
                }
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 10)
    }

    private func gradient(for kind: BenchmarkTestKind) -> LinearGradient {
        switch kind {
        case .sequentialWrite:
            return LinearGradient(
                colors: [Color(red: 0.80, green: 0.35, blue: 0.22), Color(red: 0.55, green: 0.19, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sequentialRead:
            return LinearGradient(
                colors: [Color(red: 0.14, green: 0.48, blue: 0.42), Color(red: 0.08, green: 0.25, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .randomWrite:
            return LinearGradient(
                colors: [Color(red: 0.21, green: 0.37, blue: 0.67), Color(red: 0.12, green: 0.18, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .randomRead:
            return LinearGradient(
                colors: [Color(red: 0.52, green: 0.41, blue: 0.14), Color(red: 0.31, green: 0.24, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))

            Text(value)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
    }
}

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.46))

            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.76))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.05))
        )
    }
}

private struct SparklineView: View {
    let samples: [ProgressSample]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let paddedSamples = samples.isEmpty ? placeholderSamples : samples
            let minValue = paddedSamples.map(\.value).min() ?? 0
            let maxValue = paddedSamples.map(\.value).max() ?? 1
            let normalizedMax = max(maxValue, minValue + 1)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.05))

                grid(in: size)
                    .stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))

                areaPath(in: size, samples: paddedSamples, minValue: minValue, maxValue: normalizedMax)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.47, blue: 0.43).opacity(0.32),
                                Color(red: 0.12, green: 0.47, blue: 0.43).opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(in: size, samples: paddedSamples, minValue: minValue, maxValue: normalizedMax)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.81, green: 0.33, blue: 0.22),
                                Color(red: 0.11, green: 0.45, blue: 0.42)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    private var placeholderSamples: [ProgressSample] {
        [
            ProgressSample(elapsed: 0, value: 10),
            ProgressSample(elapsed: 1, value: 24),
            ProgressSample(elapsed: 2, value: 18),
            ProgressSample(elapsed: 3, value: 30),
            ProgressSample(elapsed: 4, value: 20)
        ]
    }

    private func grid(in size: CGSize) -> Path {
        var path = Path()
        let rows = 4
        for row in 1..<rows {
            let y = size.height * CGFloat(row) / CGFloat(rows)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        return path
    }

    private func linePath(
        in size: CGSize,
        samples: [ProgressSample],
        minValue: Double,
        maxValue: Double
    ) -> Path {
        var path = Path()
        guard let firstPoint = point(at: 0, in: size, samples: samples, minValue: minValue, maxValue: maxValue) else {
            return path
        }

        path.move(to: firstPoint)
        for index in samples.indices.dropFirst() {
            if let nextPoint = point(at: index, in: size, samples: samples, minValue: minValue, maxValue: maxValue) {
                path.addLine(to: nextPoint)
            }
        }
        return path
    }

    private func areaPath(
        in size: CGSize,
        samples: [ProgressSample],
        minValue: Double,
        maxValue: Double
    ) -> Path {
        var path = linePath(in: size, samples: samples, minValue: minValue, maxValue: maxValue)
        guard let last = point(at: samples.count - 1, in: size, samples: samples, minValue: minValue, maxValue: maxValue),
              let first = point(at: 0, in: size, samples: samples, minValue: minValue, maxValue: maxValue) else {
            return path
        }

        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: first.x, y: size.height))
        path.closeSubpath()
        return path
    }

    private func point(
        at index: Int,
        in size: CGSize,
        samples: [ProgressSample],
        minValue: Double,
        maxValue: Double
    ) -> CGPoint? {
        guard samples.indices.contains(index) else { return nil }
        let item = samples[index]
        let xFraction = samples.count == 1 ? 0 : CGFloat(index) / CGFloat(samples.count - 1)
        let yFraction = CGFloat((item.value - minValue) / (maxValue - minValue))
        let x = xFraction * size.width
        let y = size.height - (yFraction * size.height)
        return CGPoint(x: x, y: y)
    }
}
