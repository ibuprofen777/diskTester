import Foundation
import Darwin

struct VolumeInfo: Sendable {
    let volumeName: String
    let mountPoint: String
    let fileSystemName: String
    let formatDescription: String
    let connectionProtocol: String?
    let isNetworkVolume: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let isInternal: Bool?
    let isRemovable: Bool?
    let isEjectable: Bool?
}

enum SystemInspector {
    static func volumeInfo(for url: URL) throws -> VolumeInfo {
        let standardizedURL = url.standardizedFileURL
        var fileSystemInfo = statfs()

        let status = standardizedURL.withUnsafeFileSystemRepresentation { fileSystemPath in
            guard let fileSystemPath else { return Int32(-1) }
            return statfs(fileSystemPath, &fileSystemInfo)
        }

        if status != 0 {
            throw BenchmarkEngineError.message("读取卷信息失败：\(String(cString: strerror(errno))).")
        }

        let resourceValues = try standardizedURL.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ])

        let fileSystemName = string(from: fileSystemInfo.f_fstypename)
        let mountPoint = string(from: fileSystemInfo.f_mntonname)
        let diskUtilityInfo = diskUtilityVolumeInfo(forMountPoint: mountPoint)
        let networkProtocol = networkProtocolName(forFileSystem: fileSystemName)
        let statfsTotalCapacity = capacityFromStatfsBlocks(fileSystemInfo.f_blocks, blockSize: fileSystemInfo.f_bsize)
        let statfsAvailableCapacity = capacityFromStatfsBlocks(fileSystemInfo.f_bavail, blockSize: fileSystemInfo.f_bsize)
        let fileManagerCapacities = fileSystemCapacities(forPath: standardizedURL.path(percentEncoded: false))
        let resolvedTotalCapacity = preferredCapacity(
            resourceValues.volumeTotalCapacity.map(Int64.init),
            fallback: statfsTotalCapacity,
            alternate: fileManagerCapacities.total
        )
        let resolvedAvailableCapacity = preferredCapacity(
            resourceValues.volumeAvailableCapacityForImportantUsage,
            fallback: resourceValues.volumeAvailableCapacity.map(Int64.init),
            alternate: statfsAvailableCapacity,
            extraFallback: fileManagerCapacities.available
        )

        return VolumeInfo(
            volumeName: resourceValues.volumeName ?? URL(fileURLWithPath: mountPoint).lastPathComponent,
            mountPoint: mountPoint,
            fileSystemName: fileSystemName,
            formatDescription: resourceValues.volumeLocalizedFormatDescription ?? fileSystemName.uppercased(),
            connectionProtocol: resolvedConnectionProtocol(from: diskUtilityInfo, fallbackNetworkProtocol: networkProtocol),
            isNetworkVolume: networkProtocol != nil,
            totalCapacity: resolvedTotalCapacity,
            availableCapacity: resolvedAvailableCapacity,
            isInternal: resourceValues.volumeIsInternal,
            isRemovable: resourceValues.volumeIsRemovable,
            isEjectable: resourceValues.volumeIsEjectable
        )
    }

    private static func string<T>(from tuple: T) -> String {
        var tuple = tuple
        return withUnsafePointer(to: &tuple) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { cString in
                String(cString: cString)
            }
        }
    }

    private static func capacityFromStatfsBlocks(_ blocks: UInt32, blockSize: UInt32) -> Int64 {
        Int64(blocks) * Int64(blockSize)
    }

    private static func capacityFromStatfsBlocks(_ blocks: UInt64, blockSize: UInt32) -> Int64 {
        Int64(blocks) * Int64(blockSize)
    }

    private static func fileSystemCapacities(forPath path: String) -> (total: Int64?, available: Int64?) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else {
            return (nil, nil)
        }

        let total = (attributes[.systemSize] as? NSNumber)?.int64Value
        let available = (attributes[.systemFreeSize] as? NSNumber)?.int64Value
        return (total, available)
    }

    private static func preferredCapacity(
        _ primary: Int64?,
        fallback: Int64?,
        alternate: Int64?,
        extraFallback: Int64? = nil
    ) -> Int64? {
        for candidate in [primary, fallback, alternate, extraFallback] {
            guard let candidate else { continue }
            if candidate > 0 {
                return candidate
            }
        }

        for candidate in [primary, fallback, alternate, extraFallback] {
            guard let candidate else { continue }
            if candidate == 0 {
                return 0
            }
        }

        return nil
    }

    private static func diskUtilityVolumeInfo(forMountPoint mountPoint: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", mountPoint]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            return nil
        }

        let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return plist as? [String: Any]
    }

    private static func resolvedConnectionProtocol(
        from diskUtilityInfo: [String: Any]?,
        fallbackNetworkProtocol: String?
    ) -> String? {
        if let busProtocol = normalizedProtocolName(diskUtilityInfo?["BusProtocol"] as? String) {
            return busProtocol
        }

        if let deviceTreePath = (diskUtilityInfo?["DeviceTreePath"] as? String)?.lowercased() {
            if deviceTreePath.contains("thunderbolt") {
                return "Thunderbolt"
            }
            if deviceTreePath.contains("usb") {
                return "USB"
            }
            if deviceTreePath.contains("nvme") || deviceTreePath.contains("pcie") || deviceTreePath.contains("apcie") {
                return "PCIe"
            }
            if deviceTreePath.contains("sata") {
                return "SATA"
            }
        }

        return fallbackNetworkProtocol
    }

    private static func normalizedProtocolName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "pci-express":
            return "PCIe"
        case "usb":
            return "USB"
        case "thunderbolt":
            return "Thunderbolt"
        case "sata":
            return "SATA"
        default:
            return trimmed
        }
    }

    private static func networkProtocolName(forFileSystem fileSystemName: String) -> String? {
        switch fileSystemName.lowercased() {
        case "smbfs", "cifs":
            return "Network / SMB"
        case "nfs":
            return "Network / NFS"
        case "afpfs":
            return "Network / AFP"
        case "webdav", "webdavfs":
            return "Network / WebDAV"
        default:
            return nil
        }
    }
}
