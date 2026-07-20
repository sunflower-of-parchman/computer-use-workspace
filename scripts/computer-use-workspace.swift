import AppKit
import ApplicationServices
import CoreGraphics
import CryptoKit
import Darwin
import Foundation

private struct Rect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var area: Double { max(0, width) * max(0, height) }
}

private extension CGRect {
    var areaValue: Double { isNull || isEmpty ? 0 : Double(width * height) }
}

private struct DisplayInfo: Codable, Equatable {
    var id: UInt32
    var frame: Rect
    var visibleFrame: Rect
    var isMain: Bool
}

private struct WindowInfo: Codable, Equatable {
    var id: UInt32
    var pid: Int32
    var bundleIdentifier: String?
    var bounds: Rect
    var layer: Int
}

private struct DesktopSnapshot: Codable {
    var capturedAt: Double
    var accessibilityTrusted: Bool
    var frontmostBundleIdentifier: String?
    var focusedDisplayID: UInt32?
    var pointerDisplayID: UInt32?
    var displays: [DisplayInfo]
    var windows: [WindowInfo]
}

private struct Reservation: Codable, Equatable {
    var id: String
    var app: String
    var createdAt: Double
    var expiresAt: Double
    var protectedDisplayID: UInt32?
    var targetDisplayID: UInt32
    var region: Rect
    var baselineWindowIDs: [UInt32]
    var appWasRunning: Bool
    var batchID: String?
}

private struct RestoreRecord: Codable, Equatable {
    var reservationID: String
    var app: String
    var pid: Int32
    var windowID: UInt32
    var originalBounds: Rect
    var targetRegion: Rect
    var createdAt: Double
    var appWasRunning: Bool
    var ownershipDigest: String? = nil
}

private struct PersistentState: Codable {
    var reservations: [Reservation] = []
    var restores: [RestoreRecord] = []
    var batches: [BatchPlan] = []
    var geometryProfiles: [WindowGeometryProfile] = []

    private enum CodingKeys: String, CodingKey {
        case reservations
        case restores
        case batches
        case geometryProfiles
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reservations = try container.decodeIfPresent([Reservation].self, forKey: .reservations) ?? []
        restores = try container.decodeIfPresent([RestoreRecord].self, forKey: .restores) ?? []
        batches = try container.decodeIfPresent([BatchPlan].self, forKey: .batches) ?? []
        geometryProfiles = try container.decodeIfPresent([WindowGeometryProfile].self, forKey: .geometryProfiles) ?? []
    }
}

private struct PlacementChoice {
    var display: DisplayInfo
    var region: CGRect
}

private struct SizeValue: Codable, Equatable {
    var width: Double
    var height: Double

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var cgSize: CGSize { CGSize(width: width, height: height) }
    var area: Double { width * height }
}

private struct BatchRequestItem: Codable, Equatable {
    var app: String
    var width: Double
    var height: Double
    var launchWidth: Double?
    var launchHeight: Double?
    var minimumWidth: Double?
    var minimumHeight: Double?
    var resizable: Bool?
}

private struct WindowGeometryProfile: Codable, Equatable {
    var app: String
    var launchSize: SizeValue
    var minimumSize: SizeValue
    var resizable: Bool?
    var source: String
    var observedAt: Double?
}

private enum BatchItemStatus: String, Codable {
    case planned
    case placed
    case failed
}

private enum BatchStatus: String, Codable {
    case planned
    case active
    case failed
    case completed
}

private struct BatchPlanItem: Codable, Equatable {
    var app: String
    var reservationID: String
    var requestedSize: SizeValue
    var plannedSize: SizeValue
    var targetDisplayID: UInt32
    var region: Rect
    var geometrySource: String
    var resizable: Bool?
    var status: BatchItemStatus
    var actualLaunchBounds: Rect?
    var windowID: UInt32? = nil
    var pid: Int32? = nil
    var finalBounds: Rect? = nil
}

private struct BatchPlan: Codable, Equatable {
    var id: String
    var createdAt: Double
    var expiresAt: Double
    var protectedDisplayID: UInt32?
    var status: BatchStatus
    var launchOrder: [String]
    var items: [BatchPlanItem]
    var failureReason: String?
    var baselineFrontmostBundleIdentifier: String? = nil
    var baselineDisplays: [DisplayInfo]? = nil
    var baselineWindows: [WindowInfo]? = nil
    var layoutVariant: Int? = nil
}

private struct ResolvedBatchItem {
    var requestIndex: Int
    var request: BatchRequestItem
    var plannedSize: CGSize
    var profile: WindowGeometryProfile
}

private struct BatchPlacement {
    var requestIndex: Int
    var display: DisplayInfo
    var region: CGRect
}

private struct PointValue: Codable, Equatable {
    var x: Double
    var y: Double
}

private struct ComputerUseDrag: Codable {
    var app: String
    var purpose: String
    var coordinateSpace: String
    var windowOrigin: PointValue
    var from: PointValue
    var to: PointValue
}

private struct PrepareOutput: Codable {
    var ok: Bool
    var status: String
    var reservationID: String?
    var app: String
    var protectedDisplayID: UInt32?
    var targetDisplayID: UInt32?
    var region: Rect?
    var expiresAt: Double?
    var appWasRunning: Bool?
    var plannedSize: SizeValue?
    var geometrySource: String?
    var geometryCertain: Bool?
    var resizable: Bool?
    var dryRun: Bool
    var message: String
}

private struct BatchPreflightOutput: Codable {
    var ok: Bool
    var status: String
    var batchID: String?
    var protectedDisplayID: UInt32?
    var launchOrder: [String]
    var items: [BatchPlanItem]
    var unknownApps: [String]
    var dryRun: Bool
    var message: String
    var baselineSummary: BaselineSummary? = nil
    var baseline: DesktopSnapshot? = nil
}

private struct BaselineSummary: Codable {
    var capturedAt: Double
    var frontmostBundleIdentifier: String?
    var focusedDisplayID: UInt32?
    var displayCount: Int
    var windowCount: Int
}

private struct BatchReplanResult {
    var reservation: Reservation
    var replanned: Bool
    var failureReason: String?
}

private struct ProofWindowResult: Codable {
    var app: String
    var reservationID: String
    var windowID: UInt32?
    var region: Rect
    var currentBounds: Rect?
    var displayID: UInt32?
    var present: Bool
    var reservationContained: Bool
    var displayContained: Bool
}

private struct BaselineWindowResult: Codable {
    var windowID: UInt32
    var bundleIdentifier: String?
    var baselineBounds: Rect
    var currentBounds: Rect?
    var present: Bool
    var boundsEqual: Bool
    var boundsDelta: Double?
}

private struct OverlapResult: Codable {
    var firstReservationID: String
    var secondReservationID: String
}

private struct BatchProof: Codable {
    var batchID: String
    var complete: Bool
    var ok: Bool
    var ownershipAuthenticated: Bool
    var proofWindows: [ProofWindowResult]
    var remainingReservations: [Reservation]
    var baselineWindows: [BaselineWindowResult]
    var baselineWindowsEqual: Bool
    var pairwiseDisjoint: Bool
    var overlaps: [OverlapResult]
    var allWindowsInReservations: Bool
    var allWindowsOnDisplays: Bool
    var expectedFrontmostBundleIdentifier: String?
    var currentFrontmostBundleIdentifier: String?
    var frontmostRestored: Bool
}

private struct BatchProofSummary: Codable {
    var batchID: String
    var complete: Bool
    var ok: Bool
    var ownershipAuthenticated: Bool
    var baselineWindowsEqual: Bool
    var changedBaselineWindowIDs: [UInt32]
    var pairwiseDisjoint: Bool
    var overlaps: [OverlapResult]
    var allWindowsInReservations: Bool
    var allWindowsOnDisplays: Bool
    var frontmostRestored: Bool
}

private struct ActionOutput: Codable {
    var ok: Bool
    var status: String
    var reservationID: String?
    var app: String?
    var windowID: UInt32?
    var originalBounds: Rect?
    var currentBounds: Rect?
    var targetRegion: Rect?
    var computerUseDrag: ComputerUseDrag?
    var computerUseDrags: [ComputerUseDrag]? = nil
    var batchID: String? = nil
    var batchStatus: BatchStatus? = nil
    var remainingReservations: [Reservation]? = nil
    var proofSummary: BatchProofSummary? = nil
    var focusRestored: Bool? = nil
    var batch: BatchPlan? = nil
    var proof: BatchProof? = nil
    var snapshot: DesktopSnapshot? = nil
    var lifecycleReceipt: String? = nil
    var message: String
}

private struct ProveOutput: Codable {
    var ok: Bool
    var status: String
    var batchID: String
    var focusRestored: Bool
    var batch: BatchPlan
    var proof: BatchProof
    var snapshot: DesktopSnapshot
    var message: String
}

private struct SimpleOutput: Codable {
    var ok: Bool
    var status: String
    var message: String
}

private struct WindowSafety: Codable, Equatable {
    var edited: Bool?
    var modal: Bool?
    var hasSheet: Bool
    var hasCloseButton: Bool
}

private enum CleanupAction: String, Codable {
    case alreadyClosed = "already_closed"
    case closeCreatedWindow = "close_created_window"
    case closeWindowThenQuit = "close_window_then_quit"
    case leaveOpen = "leave_open"
    case preserveEdited = "preserve_edited"
    case preserveModal = "preserve_modal"
}

private struct FinishOutput: Codable {
    var ok: Bool
    var status: String
    var reservationID: String
    var app: String
    var appWasRunning: Bool
    var windowID: UInt32
    var windowPresent: Bool
    var safety: WindowSafety?
    var plannedAction: CleanupAction
    var applied: Bool
    var appTerminated: Bool?
    var message: String
}

private struct BatchFinishItemOutput: Codable {
    var app: String
    var reservationID: String
    var result: FinishOutput?
    var status: String
    var applied: Bool
    var message: String
}

private struct BatchFinishOutput: Codable {
    var ok: Bool
    var status: String
    var batchID: String
    var applied: Bool
    var leaveOpen: Bool
    var items: [BatchFinishItemOutput]
    var message: String
}

private enum WorkspaceError: Error, CustomStringConvertible {
    case usage(String)
    case runtime(String)

    var description: String {
        switch self {
        case .usage(let message), .runtime(let message): return message
        }
    }
}

private struct Arguments {
    let command: String
    let options: [String: String]
    let flags: Set<String>

    init(_ values: [String]) throws {
        guard let first = values.first else { throw WorkspaceError.usage(usageText) }
        command = first
        var parsedOptions: [String: String] = [:]
        var parsedFlags: Set<String> = []
        var index = 1
        while index < values.count {
            let value = values[index]
            guard value.hasPrefix("--") else {
                throw WorkspaceError.usage("Unexpected argument: \(value)")
            }
            if index + 1 < values.count, !values[index + 1].hasPrefix("--") {
                parsedOptions[value] = values[index + 1]
                index += 2
            } else {
                parsedFlags.insert(value)
                index += 1
            }
        }
        options = parsedOptions
        flags = parsedFlags
    }

    func required(_ name: String) throws -> String {
        guard let value = options[name], !value.isEmpty else {
            throw WorkspaceError.usage("Missing required option \(name)")
        }
        return value
    }

    func double(_ name: String, default fallback: Double) throws -> Double {
        guard let raw = options[name] else { return fallback }
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw WorkspaceError.usage("\(name) must be a positive number")
        }
        return value
    }

    func stringMap(_ name: String) throws -> [String: String] {
        let raw = try required(name)
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw WorkspaceError.usage("\(name) must be a JSON object whose keys and values are strings")
        }
        return value
    }

    func optionalStringMap(_ name: String) throws -> [String: String] {
        guard options[name] != nil else { return [:] }
        return try stringMap(name)
    }
}

private let usageText = """
Usage:
  computer-use-workspace scan
  computer-use-workspace preflight --request JSON [--ttl 180] [--layout-variant 0] [--dry-run] [--verbose]
  computer-use-workspace batch-status --batch ID
  computer-use-workspace prove --batch ID --receipts JSON [--restore-focus]
  computer-use-workspace finish-batch --batch ID --receipts JSON [--apply] [--leave-open]
  computer-use-workspace prepare --app BUNDLE_ID [--width 900] [--height 700] [--ttl 90] [--dry-run]
  computer-use-workspace place --reservation ID [--receipts JSON] [--wait 6] [--verbose]
  computer-use-workspace verify --reservation ID --receipt RECEIPT [--receipts JSON] [--verbose]
  computer-use-workspace restore --reservation ID --receipt RECEIPT
  computer-use-workspace finish --reservation ID --receipt RECEIPT [--apply] [--leave-open] [--confirm-closed]
  computer-use-workspace release --reservation ID
  computer-use-workspace self-test
"""

private let encoder: JSONEncoder = {
    let value = JSONEncoder()
    value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return value
}()

private func emit<T: Encodable>(_ value: T) {
    do {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
        fputs("Unable to encode output: \(error)\n", stderr)
        exit(2)
    }
}

private final class StateStore {
    private let stateURL: URL
    private let lockPath: String

    init() {
        let base = "/private/tmp/computer-use-workspace-\(getuid())"
        stateURL = URL(fileURLWithPath: base + ".json")
        lockPath = base + ".lock"
    }

    func withState<T>(_ body: (inout PersistentState) throws -> T) throws -> T {
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw WorkspaceError.runtime("Unable to open the reservation lock")
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw WorkspaceError.runtime("Unable to lock the reservation registry")
        }
        defer { flock(descriptor, LOCK_UN) }

        var state = readState()
        prune(&state)
        let result = try body(&state)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
        guard chmod(stateURL.path, S_IRUSR | S_IWUSR) == 0 else {
            throw WorkspaceError.runtime("Unable to secure the lifecycle registry")
        }
        return result
    }

    func read<T>(_ body: (PersistentState) throws -> T) throws -> T {
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw WorkspaceError.runtime("Unable to open the reservation lock")
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_SH) == 0 else {
            throw WorkspaceError.runtime("Unable to lock the reservation registry")
        }
        defer { flock(descriptor, LOCK_UN) }

        var state = readState()
        prune(&state)
        return try body(state)
    }

    private func prune(_ state: inout PersistentState) {
        let now = Date().timeIntervalSince1970
        state.reservations.removeAll { $0.expiresAt <= now }
        state.restores.removeAll { now - $0.createdAt > 86_400 }
        state.batches.removeAll { $0.expiresAt <= now }
        state.geometryProfiles.removeAll { profile in
            profile.observedAt.map { now - $0 > 2_592_000 } ?? false
        }
        if state.geometryProfiles.count > 64 {
            state.geometryProfiles.sort { ($0.observedAt ?? 0) > ($1.observedAt ?? 0) }
            state.geometryProfiles = Array(state.geometryProfiles.prefix(64))
        }
    }

    private func readState() -> PersistentState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistentState.self, from: data) else {
            return PersistentState()
        }
        return state
    }
}

private struct OwnershipPayload: Encodable {
    var reservationID: String
    var app: String
    var pid: Int32
    var windowID: UInt32
    var originalBounds: Rect
    var targetRegion: Rect
    var createdAt: Double
    var appWasRunning: Bool
}

private func ownershipDigest(receipt: String, record: RestoreRecord) throws -> String {
    let payload = OwnershipPayload(
        reservationID: record.reservationID,
        app: record.app,
        pid: record.pid,
        windowID: record.windowID,
        originalBounds: record.originalBounds,
        targetRegion: record.targetRegion,
        createdAt: record.createdAt,
        appWasRunning: record.appWasRunning
    )
    var material = Data(receipt.utf8)
    material.append(0)
    material.append(try encoder.encode(payload))
    return SHA256.hash(data: material).map { String(format: "%02x", $0) }.joined()
}

private func makeOwnedRestoreRecord(
    reservation: Reservation,
    window: WindowInfo,
    originalBounds: CGRect
) throws -> (record: RestoreRecord, receipt: String) {
    let receipt = UUID().uuidString.lowercased() + UUID().uuidString.lowercased()
    var record = RestoreRecord(
        reservationID: reservation.id,
        app: reservation.app,
        pid: window.pid,
        windowID: window.id,
        originalBounds: Rect(originalBounds),
        targetRegion: reservation.region,
        createdAt: Date().timeIntervalSince1970,
        appWasRunning: reservation.appWasRunning
    )
    record.ownershipDigest = try ownershipDigest(receipt: receipt, record: record)
    return (record, receipt)
}

private func constantTimeEqual(_ first: String, _ second: String) -> Bool {
    let left = Array(first.utf8)
    let right = Array(second.utf8)
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices {
        difference |= left[index] ^ right[index]
    }
    return difference == 0
}

private func authenticate(_ record: RestoreRecord, receipt: String) throws {
    guard let expected = record.ownershipDigest else {
        throw WorkspaceError.runtime("Lifecycle record predates ownership receipts; preserve the window and release the stale record without cleanup")
    }
    let actual = try ownershipDigest(receipt: receipt, record: record)
    guard constantTimeEqual(actual, expected) else {
        throw WorkspaceError.runtime("Lifecycle receipt does not match the recorded task-owned window")
    }
}

private func appKitRectToQuartz(_ rect: NSRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.origin.x, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
}

private func desktopSnapshot() throws -> DesktopSnapshot {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let screens = NSScreen.screens
    guard !screens.isEmpty else { throw WorkspaceError.runtime("No active displays were found") }

    let mainDisplayID = CGMainDisplayID()
    let primaryScreen = screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainDisplayID
    } ?? screens[0]
    let primaryHeight = primaryScreen.frame.height

    let displays: [DisplayInfo] = screens.compactMap { screen in
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let id = number.uint32Value
        return DisplayInfo(
            id: id,
            frame: Rect(appKitRectToQuartz(screen.frame, primaryHeight: primaryHeight)),
            visibleFrame: Rect(appKitRectToQuartz(screen.visibleFrame, primaryHeight: primaryHeight)),
            isMain: id == mainDisplayID
        )
    }

    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    var bundleCache: [Int32: String?] = [:]
    var windows: [WindowInfo] = []
    for raw in rawWindows {
        guard let windowNumber = raw[kCGWindowNumber as String] as? NSNumber,
              let ownerPID = raw[kCGWindowOwnerPID as String] as? NSNumber,
              let layerNumber = raw[kCGWindowLayer as String] as? NSNumber,
              let boundsDictionary = raw[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            continue
        }
        let pid = ownerPID.int32Value
        if bundleCache[pid] == nil {
            bundleCache[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        let layer = layerNumber.intValue
        guard layer == 0, bounds.width >= 80, bounds.height >= 60 else { continue }
        windows.append(WindowInfo(
            id: windowNumber.uint32Value,
            pid: pid,
            bundleIdentifier: bundleCache[pid] ?? nil,
            bounds: Rect(bounds),
            layer: layer
        ))
    }

    let frontmost = NSWorkspace.shared.frontmostApplication
    let frontmostPID = frontmost?.processIdentifier
    let focusedWindow = windows.first { $0.pid == frontmostPID }
    let focusedDisplayID = focusedWindow.flatMap { window in
        displayContaining(window.bounds.cgRect, displays: displays)
    }

    let pointerInAppKit = NSEvent.mouseLocation
    let pointerInQuartz = CGPoint(x: pointerInAppKit.x, y: primaryHeight - pointerInAppKit.y)
    let pointerDisplayID = displays.first { $0.frame.cgRect.contains(pointerInQuartz) }?.id

    return DesktopSnapshot(
        capturedAt: Date().timeIntervalSince1970,
        accessibilityTrusted: AXIsProcessTrusted(),
        frontmostBundleIdentifier: frontmost?.bundleIdentifier,
        focusedDisplayID: focusedDisplayID ?? pointerDisplayID,
        pointerDisplayID: pointerDisplayID,
        displays: displays,
        windows: windows
    )
}

private func exactWindowInfo(id: UInt32, pid: Int32) -> WindowInfo? {
    let rawWindows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
    guard let raw = rawWindows.first,
          let windowNumber = raw[kCGWindowNumber as String] as? NSNumber,
          windowNumber.uint32Value == id,
          let ownerPID = raw[kCGWindowOwnerPID as String] as? NSNumber,
          ownerPID.int32Value == pid,
          let layerNumber = raw[kCGWindowLayer as String] as? NSNumber,
          layerNumber.intValue == 0,
          let boundsDictionary = raw[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
          bounds.width >= 80,
          bounds.height >= 60 else {
        return nil
    }
    return WindowInfo(
        id: id,
        pid: pid,
        bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
        bounds: Rect(bounds),
        layer: 0
    )
}

private func displayContaining(_ rect: CGRect, displays: [DisplayInfo]) -> UInt32? {
    displays.max { first, second in
        first.frame.cgRect.intersection(rect).areaValue < second.frame.cgRect.intersection(rect).areaValue
    }.flatMap { display in
        display.frame.cgRect.intersects(rect) ? display.id : nil
    }
}

private func padded(_ rect: CGRect, by amount: CGFloat, clippedTo bounds: CGRect) -> CGRect? {
    let expanded = rect.insetBy(dx: -amount, dy: -amount).intersection(bounds)
    return expanded.isNull || expanded.isEmpty ? nil : expanded
}

private func subtract(_ occupied: CGRect, from source: CGRect) -> [CGRect] {
    let intersection = source.intersection(occupied)
    guard !intersection.isNull, !intersection.isEmpty else { return [source] }
    var output: [CGRect] = []
    if intersection.minX > source.minX {
        output.append(CGRect(x: source.minX, y: source.minY, width: intersection.minX - source.minX, height: source.height))
    }
    if intersection.maxX < source.maxX {
        output.append(CGRect(x: intersection.maxX, y: source.minY, width: source.maxX - intersection.maxX, height: source.height))
    }
    if intersection.minY > source.minY {
        output.append(CGRect(x: intersection.minX, y: source.minY, width: intersection.width, height: intersection.minY - source.minY))
    }
    if intersection.maxY < source.maxY {
        output.append(CGRect(x: intersection.minX, y: intersection.maxY, width: intersection.width, height: source.maxY - intersection.maxY))
    }
    return output.filter { $0.width >= 1 && $0.height >= 1 }
}

private func choosePlacement(
    snapshot: DesktopSnapshot,
    reservations: [Reservation],
    desiredWidth: Double,
    desiredHeight: Double,
    minimumWidth requiredMinimumWidth: Double? = nil,
    minimumHeight requiredMinimumHeight: Double? = nil,
    ignoringWindowIDs: Set<UInt32> = [],
    ignoringReservationIDs: Set<String> = []
) -> PlacementChoice? {
    let protectedID = snapshot.focusedDisplayID
    let minimumWidth = requiredMinimumWidth ?? min(480, desiredWidth)
    let minimumHeight = requiredMinimumHeight ?? min(320, desiredHeight)
    var choices: [PlacementChoice] = []

    for display in snapshot.displays {
        let visible = display.visibleFrame.cgRect
        var freeRects = [visible]
        let windowRects = snapshot.windows.filter { window in
            !ignoringWindowIDs.contains(window.id)
        }.compactMap { window in
            padded(window.bounds.cgRect, by: 12, clippedTo: visible)
        }
        let reservationRects = reservations.filter { reservation in
            !ignoringReservationIDs.contains(reservation.id)
        }.compactMap { reservation in
            reservation.targetDisplayID == display.id ? padded(reservation.region.cgRect, by: 12, clippedTo: visible) : nil
        }
        for occupied in windowRects + reservationRects {
            freeRects = freeRects.flatMap { subtract(occupied, from: $0) }
            if freeRects.isEmpty { break }
        }
        for free in freeRects where free.width >= minimumWidth && free.height >= minimumHeight {
            let width = min(CGFloat(desiredWidth), free.width)
            let height = min(CGFloat(desiredHeight), free.height)
            let region = CGRect(x: free.minX, y: free.minY, width: width, height: height)
            choices.append(PlacementChoice(display: display, region: region))
        }
    }

    return choices.max { first, second in
        let firstIsProtected = first.display.id == protectedID
        let secondIsProtected = second.display.id == protectedID
        if firstIsProtected != secondIsProtected {
            return firstIsProtected && !secondIsProtected
        }
        let firstScore = first.region.areaValue
        let secondScore = second.region.areaValue
        if firstScore == secondScore {
            if first.region.minY == second.region.minY { return first.region.minX > second.region.minX }
            return first.region.minY > second.region.minY
        }
        return firstScore < secondScore
    }
}

private let builtInGeometryProfiles: [String: WindowGeometryProfile] = {
    let values = [
        WindowGeometryProfile(
            app: "com.apple.Chess",
            launchSize: SizeValue(width: 971, height: 712),
            minimumSize: SizeValue(width: 971, height: 712),
            resizable: nil,
            source: "built_in_live_observation",
            observedAt: nil
        ),
        WindowGeometryProfile(
            app: "com.apple.SystemProfiler",
            launchSize: SizeValue(width: 902, height: 602),
            minimumSize: SizeValue(width: 902, height: 602),
            resizable: nil,
            source: "built_in_live_observation",
            observedAt: nil
        ),
        WindowGeometryProfile(
            app: "com.apple.FontBook",
            launchSize: SizeValue(width: 1000, height: 650),
            minimumSize: SizeValue(width: 1000, height: 650),
            resizable: false,
            source: "built_in_proven_minimum",
            observedAt: nil
        ),
        WindowGeometryProfile(
            app: "com.apple.Dictionary",
            launchSize: SizeValue(width: 690, height: 624),
            minimumSize: SizeValue(width: 690, height: 624),
            resizable: nil,
            source: "built_in_live_observation",
            observedAt: nil
        ),
        WindowGeometryProfile(
            app: "com.apple.calculator",
            launchSize: SizeValue(width: 230, height: 408),
            minimumSize: SizeValue(width: 230, height: 408),
            resizable: false,
            source: "built_in_proven_minimum",
            observedAt: nil
        )
    ]
    return Dictionary(uniqueKeysWithValues: values.map { ($0.app, $0) })
}()

private func resolvedGeometry(
    for request: BatchRequestItem,
    cachedProfiles: [WindowGeometryProfile]
) -> WindowGeometryProfile? {
    if let launchWidth = request.launchWidth,
       let launchHeight = request.launchHeight,
       launchWidth > 0,
       launchHeight > 0 {
        let minimumWidth = request.minimumWidth ?? launchWidth
        let minimumHeight = request.minimumHeight ?? launchHeight
        guard minimumWidth > 0, minimumHeight > 0 else { return nil }
        return WindowGeometryProfile(
            app: request.app,
            launchSize: SizeValue(width: launchWidth, height: launchHeight),
            minimumSize: SizeValue(width: minimumWidth, height: minimumHeight),
            resizable: request.resizable,
            source: "explicit_request",
            observedAt: nil
        )
    }

    let cached = cachedProfiles
        .filter { $0.app == request.app }
        .max { ($0.observedAt ?? 0) < ($1.observedAt ?? 0) }
    guard let builtIn = builtInGeometryProfiles[request.app] else { return cached }
    guard let cached else { return builtIn }

    return WindowGeometryProfile(
        app: request.app,
        launchSize: SizeValue(
            width: max(builtIn.launchSize.width, cached.launchSize.width),
            height: max(builtIn.launchSize.height, cached.launchSize.height)
        ),
        minimumSize: SizeValue(
            width: max(builtIn.minimumSize.width, cached.minimumSize.width),
            height: max(builtIn.minimumSize.height, cached.minimumSize.height)
        ),
        resizable: builtIn.resizable == false || cached.resizable == false
            ? false
            : (builtIn.resizable == true && cached.resizable == true ? true : nil),
        source: "built_in_plus_observed",
        observedAt: cached.observedAt
    )
}

private func plannedSize(for request: BatchRequestItem, profile: WindowGeometryProfile) -> CGSize {
    if profile.resizable == true {
        return CGSize(
            width: max(request.width, profile.minimumSize.width),
            height: max(request.height, profile.minimumSize.height)
        )
    }
    return CGSize(
        width: max(request.width, profile.launchSize.width, profile.minimumSize.width),
        height: max(request.height, profile.launchSize.height, profile.minimumSize.height)
    )
}

private func candidateBatchPlacements(
    size: CGSize,
    snapshot: DesktopSnapshot,
    occupiedByDisplay: [UInt32: [CGRect]]
) -> [(display: DisplayInfo, region: CGRect, waste: Double)] {
    var candidates: [(display: DisplayInfo, region: CGRect, waste: Double)] = []
    for display in snapshot.displays {
        let visible = display.visibleFrame.cgRect
        guard visible.width >= size.width, visible.height >= size.height else { continue }
        let occupied = occupiedByDisplay[display.id] ?? []
        var xOrigins: Set<CGFloat> = [visible.minX, visible.maxX - size.width]
        var yOrigins: Set<CGFloat> = [visible.minY, visible.maxY - size.height]
        for rect in occupied {
            xOrigins.insert(rect.maxX)
            xOrigins.insert(rect.minX - size.width)
            yOrigins.insert(rect.maxY)
            yOrigins.insert(rect.minY - size.height)
        }
        for x in xOrigins.sorted() {
            for y in yOrigins.sorted() {
                let region = CGRect(x: x, y: y, width: size.width, height: size.height)
                guard visible.contains(region), occupied.allSatisfy({ !$0.intersects(region) }) else { continue }
                let nearestGap = occupied.map { rect -> Double in
                    let horizontal = max(0, max(rect.minX - region.maxX, region.minX - rect.maxX))
                    let vertical = max(0, max(rect.minY - region.maxY, region.minY - rect.maxY))
                    return Double(horizontal + vertical)
                }.min() ?? 0
                candidates.append((display, region, nearestGap))
            }
        }
    }
    return candidates.sorted { first, second in
        let firstProtected = first.display.id == snapshot.focusedDisplayID
        let secondProtected = second.display.id == snapshot.focusedDisplayID
        if firstProtected != secondProtected { return !firstProtected }
        if first.waste != second.waste { return first.waste < second.waste }
        if first.region.minY != second.region.minY { return first.region.minY < second.region.minY }
        return first.region.minX < second.region.minX
    }
}

private func solveBatchPlacements(
    items: [ResolvedBatchItem],
    snapshot: DesktopSnapshot,
    reservations: [Reservation],
    ignoringWindowIDs: Set<UInt32> = [],
    ignoringReservationIDs: Set<String> = [],
    layoutVariant: Int = 0
) -> [BatchPlacement]? {
    guard !items.isEmpty, items.count <= 8 else { return nil }
    var occupiedByDisplay: [UInt32: [CGRect]] = [:]

    for display in snapshot.displays {
        let visible = display.visibleFrame.cgRect
        let windowRects = snapshot.windows.filter { window in
            !ignoringWindowIDs.contains(window.id)
        }.compactMap { window in
            padded(window.bounds.cgRect, by: 12, clippedTo: visible)
        }
        let reservationRects = reservations.filter { reservation in
            reservation.targetDisplayID == display.id && !ignoringReservationIDs.contains(reservation.id)
        }.compactMap { reservation in
            padded(reservation.region.cgRect, by: 12, clippedTo: visible)
        }
        occupiedByDisplay[display.id] = windowRects + reservationRects
    }

    let ordered = items.sorted { first, second in
        if first.plannedSize.width * first.plannedSize.height == second.plannedSize.width * second.plannedSize.height {
            return first.requestIndex < second.requestIndex
        }
        return first.plannedSize.width * first.plannedSize.height > second.plannedSize.width * second.plannedSize.height
    }
    var solution: [BatchPlacement] = []

    func search(_ index: Int) -> Bool {
        if index == ordered.count { return true }
        let item = ordered[index]
        let candidates = candidateBatchPlacements(
            size: item.plannedSize,
            snapshot: snapshot,
            occupiedByDisplay: occupiedByDisplay
        )
        let boundedCandidates = Array(candidates.prefix(96))
        let offset = boundedCandidates.isEmpty ? 0 : layoutVariant % boundedCandidates.count
        let variantCandidates = Array(boundedCandidates.dropFirst(offset) + boundedCandidates.prefix(offset))
        for candidate in variantCandidates {
            let visible = candidate.display.visibleFrame.cgRect
            guard let paddedRegion = padded(candidate.region, by: 12, clippedTo: visible) else { continue }
            occupiedByDisplay[candidate.display.id, default: []].append(paddedRegion)
            solution.append(BatchPlacement(
                requestIndex: item.requestIndex,
                display: candidate.display,
                region: candidate.region
            ))
            if search(index + 1) { return true }
            solution.removeLast()
            occupiedByDisplay[candidate.display.id]?.removeLast()
        }
        return false
    }

    return search(0) ? solution : nil
}

private enum GeometryMatch: Equatable {
    case none
    case unique(Int)
    case ambiguous
}

private func uniqueGeometryMatch(
    candidates: [CGRect],
    target: CGRect,
    positionTolerance: CGFloat = 8,
    sizeTolerance: CGFloat = 8
) -> GeometryMatch {
    let matches = candidates.indices.filter { index in
        let candidate = candidates[index]
        return abs(candidate.minX - target.minX) <= positionTolerance
            && abs(candidate.minY - target.minY) <= positionTolerance
            && abs(candidate.width - target.width) <= sizeTolerance
            && abs(candidate.height - target.height) <= sizeTolerance
    }
    if matches.isEmpty { return .none }
    if matches.count == 1 { return .unique(matches[0]) }
    return .ambiguous
}

private enum AXWindowMatch {
    case none
    case unique(AXUIElement)
    case ambiguous
}

private func findAXWindow(pid: Int32, matching bounds: CGRect) -> AXWindowMatch {
    let application = AXUIElementCreateApplication(pid)
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawValue) == .success,
          let windows = rawValue as? [AXUIElement] else {
        return .none
    }
    var boundedWindows: [AXUIElement] = []
    var candidateBounds: [CGRect] = []
    for window in windows {
        guard let current = axBounds(window) else { continue }
        boundedWindows.append(window)
        candidateBounds.append(current)
    }
    switch uniqueGeometryMatch(candidates: candidateBounds, target: bounds) {
    case .none:
        return .none
    case .unique(let index):
        return .unique(boundedWindows[index])
    case .ambiguous:
        return .ambiguous
    }
}

private func axBounds(_ element: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionValue,
          let sizeValue,
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        return nil
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: point, size: size)
}

private func setAXBounds(_ element: AXUIElement, rect: CGRect) -> AXError {
    var positionSettable = DarwinBoolean(false)
    var sizeSettable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &positionSettable) == .success,
          positionSettable.boolValue else {
        return .actionUnsupported
    }
    _ = AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &sizeSettable)

    var size = rect.size
    if sizeSettable.boolValue, let sizeValue = AXValueCreate(.cgSize, &size) {
        let sizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        if sizeResult != .success { return sizeResult }
    }
    var point = rect.origin
    guard let positionValue = AXValueCreate(.cgPoint, &point) else { return .failure }
    return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
}

private func axBoolean(_ element: AXUIElement, attribute: CFString) -> Bool? {
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
          let number = rawValue as? NSNumber else {
        return nil
    }
    return number.boolValue
}

private func axRole(_ element: AXUIElement) -> String? {
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &rawValue) == .success,
          let role = rawValue as? String else {
        return nil
    }
    return role
}

private func axHasSheet(_ element: AXUIElement) -> Bool {
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &rawValue) == .success,
          let children = rawValue as? [AXUIElement] else {
        return false
    }
    return children.contains { axRole($0) == (kAXSheetRole as String) }
}

private func windowSafety(_ element: AXUIElement) -> WindowSafety {
    var closeValue: CFTypeRef?
    let hasCloseButton = AXUIElementCopyAttributeValue(
        element,
        kAXCloseButtonAttribute as CFString,
        &closeValue
    ) == .success && closeValue != nil
    return WindowSafety(
        edited: axBoolean(element, attribute: kAXEditedAttribute as CFString),
        modal: axBoolean(element, attribute: kAXModalAttribute as CFString),
        hasSheet: axHasSheet(element),
        hasCloseButton: hasCloseButton
    )
}

private func closeAXWindow(_ element: AXUIElement) -> AXError {
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &rawValue) == .success,
          let rawValue,
          CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
        return .actionUnsupported
    }
    let closeButton = rawValue as! AXUIElement
    return AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
}

private func cleanupAction(
    appWasRunning: Bool,
    windowPresent: Bool,
    safety: WindowSafety?,
    leaveOpen: Bool
) -> CleanupAction {
    if leaveOpen { return .leaveOpen }
    if !windowPresent { return .alreadyClosed }
    if safety?.edited == true { return .preserveEdited }
    if safety?.modal == true || safety?.hasSheet == true { return .preserveModal }
    return appWasRunning ? .closeCreatedWindow : .closeWindowThenQuit
}

private func waitForWindowToClose(id: UInt32, pid: Int32, timeout: TimeInterval = 3) throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if exactWindowInfo(id: id, pid: pid) == nil { return true }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
}

private func gracefullyTerminate(pid: Int32, timeout: TimeInterval = 2) -> Bool {
    guard let application = NSRunningApplication(processIdentifier: pid), !application.isTerminated else {
        return true
    }
    guard application.terminate() else { return false }
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if application.isTerminated { return true }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return application.isTerminated
}

private enum TargetWindowMatch: Equatable {
    case none
    case unique(WindowInfo)
    case ambiguous([WindowInfo])
}

private func targetWindow(snapshot: DesktopSnapshot, reservation: Reservation) -> TargetWindowMatch {
    let matching = snapshot.windows.filter { $0.bundleIdentifier == reservation.app }
    let baseline = Set(reservation.baselineWindowIDs)
    let newWindows = matching.filter { !baseline.contains($0.id) }
    if newWindows.isEmpty { return .none }
    if newWindows.count == 1 { return .unique(newWindows[0]) }
    return .ambiguous(newWindows.sorted { $0.id < $1.id })
}

private func waitForUniqueTargetWindow(
    reservation: Reservation,
    timeout: TimeInterval
) throws -> (snapshot: DesktopSnapshot, match: TargetWindowMatch) {
    let deadline = Date().addingTimeInterval(timeout)
    var lastUniqueWindowID: UInt32?
    var stableObservationCount = 0
    var snapshot = try desktopSnapshot()
    var latestMatch = targetWindow(snapshot: snapshot, reservation: reservation)

    while true {
        switch latestMatch {
        case .unique(let window):
            if lastUniqueWindowID == window.id {
                stableObservationCount += 1
                if stableObservationCount >= 3 {
                    return (snapshot, .unique(window))
                }
            } else {
                lastUniqueWindowID = window.id
                stableObservationCount = 1
            }
        case .none, .ambiguous:
            lastUniqueWindowID = nil
            stableObservationCount = 0
        }
        if Date() >= deadline { return (snapshot, latestMatch) }
        Thread.sleep(forTimeInterval: 0.15)
        snapshot = try desktopSnapshot()
        latestMatch = targetWindow(snapshot: snapshot, reservation: reservation)
    }
}

private func desiredBounds(for window: WindowInfo, region: Rect) -> CGRect {
    let current = window.bounds.cgRect
    let target = region.cgRect
    let width = min(current.width, target.width)
    let height = min(current.height, target.height)
    return CGRect(x: target.minX, y: target.minY, width: width, height: height)
}

private func dragPlan(app: String, from original: CGRect, to target: CGRect) -> ComputerUseDrag {
    let sourceX = original.width / 2
    let sourceY = min(18, original.height / 4)
    let targetX = sourceX + target.minX - original.minX
    let targetY = sourceY + target.minY - original.minY
    return ComputerUseDrag(
        app: app,
        purpose: "move",
        coordinateSpace: "app_local",
        windowOrigin: PointValue(x: original.minX, y: original.minY),
        from: PointValue(x: sourceX, y: sourceY),
        to: PointValue(x: targetX, y: targetY)
    )
}

private func resizeThenMovePlans(app: String, from original: CGRect, to target: CGRect) -> [ComputerUseDrag] {
    let inset: CGFloat = 3
    let resizedAtOriginalOrigin = CGRect(origin: original.origin, size: target.size)
    return [
        ComputerUseDrag(
            app: app,
            purpose: "resize",
            coordinateSpace: "app_local",
            windowOrigin: PointValue(x: original.minX, y: original.minY),
            from: PointValue(x: original.width - inset, y: original.height - inset),
            to: PointValue(x: target.width - inset, y: target.height - inset)
        ),
        dragPlan(app: app, from: resizedAtOriginalOrigin, to: target)
    ]
}

private func waitForSettledWindow(
    id: UInt32,
    pid: Int32,
    target: CGRect,
    timeout: TimeInterval = 2
) throws -> Rect? {
    let deadline = Date().addingTimeInterval(timeout)
    var latest: Rect?
    repeat {
        if let bounds = exactWindowInfo(id: id, pid: pid)?.bounds {
            latest = bounds
            let current = bounds.cgRect
            let delta = abs(current.minX - target.minX) + abs(current.minY - target.minY)
                + abs(current.width - target.width) + abs(current.height - target.height)
            if delta <= 4 { return bounds }
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return latest
}

private func boundsDelta(_ first: CGRect, _ second: CGRect) -> CGFloat {
    abs(first.minX - second.minX) + abs(first.minY - second.minY)
        + abs(first.width - second.width) + abs(first.height - second.height)
}

private func updateObservedGeometry(
    state: inout PersistentState,
    app: String,
    launchSize: CGSize,
    resizable: Bool? = nil
) {
    let now = Date().timeIntervalSince1970
    let prior = state.geometryProfiles
        .filter { $0.app == app }
        .max { ($0.observedAt ?? 0) < ($1.observedAt ?? 0) }
    state.geometryProfiles.removeAll { $0.app == app }
    state.geometryProfiles.append(WindowGeometryProfile(
        app: app,
        launchSize: SizeValue(
            width: max(launchSize.width, prior?.launchSize.width ?? 0),
            height: max(launchSize.height, prior?.launchSize.height ?? 0)
        ),
        minimumSize: SizeValue(
            width: max(launchSize.width, prior?.minimumSize.width ?? 0),
            height: max(launchSize.height, prior?.minimumSize.height ?? 0)
        ),
        resizable: prior?.resizable == false || resizable == false
            ? false
            : (prior?.resizable == true && resizable == true ? true : nil),
        source: "observed_launch",
        observedAt: now
    ))
}

private func preflight(_ arguments: Arguments, store: StateStore) throws {
    let rawRequest = try arguments.required("--request")
    guard let data = rawRequest.data(using: .utf8) else {
        throw WorkspaceError.usage("--request must be UTF-8 JSON")
    }
    let requests: [BatchRequestItem]
    do {
        requests = try JSONDecoder().decode([BatchRequestItem].self, from: data)
    } catch {
        throw WorkspaceError.usage("--request must be a JSON array of app geometry objects: \(error)")
    }
    guard !requests.isEmpty, requests.count <= 8 else {
        throw WorkspaceError.usage("--request must contain between 1 and 8 applications")
    }
    guard requests.allSatisfy({ !$0.app.isEmpty && $0.width > 0 && $0.height > 0 }) else {
        throw WorkspaceError.usage("Every batch item needs a non-empty app and positive width and height")
    }
    guard Set(requests.map(\.app)).count == requests.count else {
        throw WorkspaceError.usage("Every app may appear only once in a batch")
    }

    let ttl = try arguments.double("--ttl", default: 180)
    let rawLayoutVariant = arguments.options["--layout-variant"] ?? "0"
    guard let layoutVariant = Int(rawLayoutVariant), layoutVariant >= 0 else {
        throw WorkspaceError.usage("--layout-variant must be a non-negative integer")
    }
    let dryRun = arguments.flags.contains("--dry-run")
    let verbose = arguments.flags.contains("--verbose")
    let snapshot = try desktopSnapshot()
    let now = Date().timeIntervalSince1970
    let output: BatchPreflightOutput = try store.withState { state in
        let resolved = requests.enumerated().compactMap { index, request -> ResolvedBatchItem? in
            guard let profile = resolvedGeometry(for: request, cachedProfiles: state.geometryProfiles) else {
                return nil
            }
            return ResolvedBatchItem(
                requestIndex: index,
                request: request,
                plannedSize: plannedSize(for: request, profile: profile),
                profile: profile
            )
        }
        let resolvedApps = Set(resolved.map { $0.request.app })
        let unknownApps = requests.map(\.app).filter { !resolvedApps.contains($0) }
        if !unknownApps.isEmpty {
            return BatchPreflightOutput(
                ok: false, status: "unknown_geometry", batchID: nil,
                protectedDisplayID: snapshot.focusedDisplayID, launchOrder: [], items: [],
                unknownApps: unknownApps, dryRun: dryRun,
                message: "A complete layout cannot be promised until every app has a bounded launch geometry profile"
            )
        }

        let runningApps = requests.map(\.app).filter { app in
            NSRunningApplication.runningApplications(withBundleIdentifier: app).contains { !$0.isTerminated }
        }
        if !runningApps.isEmpty {
            return BatchPreflightOutput(
                ok: false, status: "preexisting_apps", batchID: nil,
                protectedDisplayID: snapshot.focusedDisplayID, launchOrder: [], items: [],
                unknownApps: [], dryRun: dryRun,
                message: "Batch preflight requires apps without pre-existing processes: \(runningApps.joined(separator: ", "))"
            )
        }

        guard let placements = solveBatchPlacements(
            items: resolved,
            snapshot: snapshot,
            reservations: state.reservations,
            layoutVariant: layoutVariant
        ) else {
            return BatchPreflightOutput(
                ok: false, status: "batch_no_safe_layout", batchID: nil,
                protectedDisplayID: snapshot.focusedDisplayID, launchOrder: [], items: [],
                unknownApps: [], dryRun: dryRun,
                message: "The complete requested application group does not fit around protected windows and active reservations"
            )
        }

        let placementByIndex = Dictionary(uniqueKeysWithValues: placements.map { ($0.requestIndex, $0) })
        let batchID = UUID().uuidString.lowercased()
        let expiration = now + ttl
        let launchOrder = resolved.sorted {
            $0.plannedSize.width * $0.plannedSize.height > $1.plannedSize.width * $1.plannedSize.height
        }.map { $0.request.app }
        let items = resolved.sorted { $0.requestIndex < $1.requestIndex }.map { item -> BatchPlanItem in
            let placement = placementByIndex[item.requestIndex]!
            return BatchPlanItem(
                app: item.request.app,
                reservationID: UUID().uuidString.lowercased(),
                requestedSize: SizeValue(width: item.request.width, height: item.request.height),
                plannedSize: SizeValue(item.plannedSize),
                targetDisplayID: placement.display.id,
                region: Rect(placement.region),
                geometrySource: item.profile.source,
                resizable: item.profile.resizable,
                status: .planned,
                actualLaunchBounds: nil
            )
        }

        if !dryRun {
            let baselineByApp = Dictionary(grouping: snapshot.windows, by: { $0.bundleIdentifier ?? "" })
            state.reservations.append(contentsOf: items.map { item in
                Reservation(
                    id: item.reservationID,
                    app: item.app,
                    createdAt: now,
                    expiresAt: expiration,
                    protectedDisplayID: snapshot.focusedDisplayID,
                    targetDisplayID: item.targetDisplayID,
                    region: item.region,
                    baselineWindowIDs: baselineByApp[item.app, default: []].map(\.id),
                    appWasRunning: false,
                    batchID: batchID
                )
            })
            state.batches.append(BatchPlan(
                id: batchID,
                createdAt: now,
                expiresAt: expiration,
                protectedDisplayID: snapshot.focusedDisplayID,
                status: .planned,
                launchOrder: launchOrder,
                items: items,
                failureReason: nil,
                baselineFrontmostBundleIdentifier: snapshot.frontmostBundleIdentifier,
                baselineDisplays: snapshot.displays,
                baselineWindows: snapshot.windows,
                layoutVariant: layoutVariant
            ))
        }
        return BatchPreflightOutput(
            ok: true, status: dryRun ? "dry_run" : "batch_planned",
            batchID: dryRun ? nil : batchID,
            protectedDisplayID: snapshot.focusedDisplayID,
            launchOrder: launchOrder,
            items: items,
            unknownApps: [], dryRun: dryRun,
            message: dryRun
                ? "The complete application group fits; nothing was reserved or moved"
                : "The complete application group was reserved before launch",
            baselineSummary: BaselineSummary(
                capturedAt: snapshot.capturedAt,
                frontmostBundleIdentifier: snapshot.frontmostBundleIdentifier,
                focusedDisplayID: snapshot.focusedDisplayID,
                displayCount: snapshot.displays.count,
                windowCount: snapshot.windows.count
            ),
            baseline: verbose ? snapshot : nil
        )
    }
    emit(output)
    if !output.ok { exit(10) }
}

private func batchStatus(_ arguments: Arguments, store: StateStore) throws {
    let batchID = try arguments.required("--batch")
    let batch = try store.read { state in state.batches.first { $0.id == batchID } }
    guard let batch else {
        emit(SimpleOutput(ok: false, status: "not_found", message: "Batch not found or expired"))
        exit(3)
    }
    emit(batch)
}

private func buildBatchProof(
    batch: BatchPlan,
    snapshot: DesktopSnapshot,
    state: PersistentState,
    receipts: [String: String] = [:]
) -> BatchProof {
    let currentByID = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0) })
    let restoreByReservation = Dictionary(uniqueKeysWithValues: state.restores.map { ($0.reservationID, $0) })
    let proofWindows = batch.items.map { item -> ProofWindowResult in
        let record = restoreByReservation[item.reservationID]
        let windowID = item.windowID ?? record?.windowID
        let current = windowID.flatMap { currentByID[$0] }
        let displayID = current.flatMap { displayContaining($0.bounds.cgRect, displays: snapshot.displays) }
        let display = displayID.flatMap { id in snapshot.displays.first { $0.id == id } }
        return ProofWindowResult(
            app: item.app,
            reservationID: item.reservationID,
            windowID: windowID,
            region: item.region,
            currentBounds: current?.bounds,
            displayID: displayID,
            present: current != nil,
            reservationContained: current.map {
                item.region.cgRect.insetBy(dx: -8, dy: -8).contains($0.bounds.cgRect)
            } ?? false,
            displayContained: current.map { window in
                display?.visibleFrame.cgRect.contains(window.bounds.cgRect) == true
            } ?? false
        )
    }
    let baselineWindows = (batch.baselineWindows ?? []).map { baseline -> BaselineWindowResult in
        let current = currentByID[baseline.id]
        return BaselineWindowResult(
            windowID: baseline.id,
            bundleIdentifier: baseline.bundleIdentifier,
            baselineBounds: baseline.bounds,
            currentBounds: current?.bounds,
            present: current != nil,
            boundsEqual: current?.bounds == baseline.bounds,
            boundsDelta: current.map { Double(boundsDelta($0.bounds.cgRect, baseline.bounds.cgRect)) }
        )
    }
    let presentProofWindows = proofWindows.filter { $0.present && $0.currentBounds != nil }
    var overlaps: [OverlapResult] = []
    for firstIndex in presentProofWindows.indices {
        for secondIndex in presentProofWindows.indices where secondIndex > firstIndex {
            if presentProofWindows[firstIndex].currentBounds!.cgRect.intersects(
                presentProofWindows[secondIndex].currentBounds!.cgRect
            ) {
                overlaps.append(OverlapResult(
                    firstReservationID: presentProofWindows[firstIndex].reservationID,
                    secondReservationID: presentProofWindows[secondIndex].reservationID
                ))
            }
        }
    }
    let remaining = state.reservations.filter { $0.batchID == batch.id }
    let complete = batch.items.allSatisfy { $0.status == .placed }
        && proofWindows.allSatisfy(\.present)
    let ownershipAuthenticated = complete && batch.items.allSatisfy { item in
        guard let record = restoreByReservation[item.reservationID],
              let receipt = receipts[item.reservationID] else { return false }
        do {
            try authenticate(record, receipt: receipt)
            return true
        } catch {
            return false
        }
    }
    let baselineEqual = baselineWindows.allSatisfy { $0.present && $0.boundsEqual }
    let inReservations = proofWindows.filter(\.present).allSatisfy(\.reservationContained)
    let onDisplays = proofWindows.filter(\.present).allSatisfy(\.displayContained)
    let expectedFrontmost = batch.baselineFrontmostBundleIdentifier
    let frontmostRestored = expectedFrontmost == nil
        || snapshot.frontmostBundleIdentifier == expectedFrontmost
    return BatchProof(
        batchID: batch.id,
        complete: complete,
        ok: complete && ownershipAuthenticated && baselineEqual && overlaps.isEmpty
            && inReservations && onDisplays && frontmostRestored,
        ownershipAuthenticated: ownershipAuthenticated,
        proofWindows: proofWindows,
        remainingReservations: remaining,
        baselineWindows: baselineWindows,
        baselineWindowsEqual: baselineEqual,
        pairwiseDisjoint: overlaps.isEmpty,
        overlaps: overlaps,
        allWindowsInReservations: inReservations,
        allWindowsOnDisplays: onDisplays,
        expectedFrontmostBundleIdentifier: expectedFrontmost,
        currentFrontmostBundleIdentifier: snapshot.frontmostBundleIdentifier,
        frontmostRestored: frontmostRestored
    )
}

private func summarizeProof(_ proof: BatchProof) -> BatchProofSummary {
    BatchProofSummary(
        batchID: proof.batchID,
        complete: proof.complete,
        ok: proof.ok,
        ownershipAuthenticated: proof.ownershipAuthenticated,
        baselineWindowsEqual: proof.baselineWindowsEqual,
        changedBaselineWindowIDs: proof.baselineWindows.filter { !$0.boundsEqual }.map(\.windowID),
        pairwiseDisjoint: proof.pairwiseDisjoint,
        overlaps: proof.overlaps,
        allWindowsInReservations: proof.allWindowsInReservations,
        allWindowsOnDisplays: proof.allWindowsOnDisplays,
        frontmostRestored: proof.frontmostRestored
    )
}

private var commandLifecycleReceipts: [String: String] = [:]

private func enrichedPlaceOutput(
    _ value: ActionOutput,
    reservationID: String,
    verbose: Bool = false,
    store: StateStore
) throws -> ActionOutput {
    var output = value
    var effectiveReceipts = commandLifecycleReceipts
    if let receipt = value.lifecycleReceipt {
        effectiveReceipts[reservationID] = receipt
    }
    let initialBatch = try store.read { state in
        state.batches.first { $0.items.contains { $0.reservationID == reservationID } }
    }
    var focusRestored: Bool?
    if value.ok,
       initialBatch?.status == .completed,
       let bundleIdentifier = initialBatch?.baselineFrontmostBundleIdentifier {
        focusRestored = restoreFrontmostApplication(bundleIdentifier)
    } else if value.ok, initialBatch?.status == .completed {
        focusRestored = true
    }
    let snapshot = try desktopSnapshot()
    let context = try store.read { state -> (BatchPlan?, BatchProof?) in
        guard let batch = state.batches.first(where: {
            $0.items.contains { $0.reservationID == reservationID }
        }) else {
            return (nil, nil)
        }
        return (batch, buildBatchProof(
            batch: batch,
            snapshot: snapshot,
            state: state,
            receipts: effectiveReceipts
        ))
    }
    output.batchID = context.0?.id
    output.batchStatus = context.0?.status
    output.remainingReservations = context.1?.remainingReservations
    output.proofSummary = context.1.map(summarizeProof)
    output.focusRestored = focusRestored
    if let proof = context.1, proof.ok, value.ok {
        output.status = value.status == "verified" ? "verified_and_proved" : "placed_and_proved"
        output.message += "; complete batch proof passed and baseline focus was restored"
    } else if let proof = context.1, proof.complete, !proof.ownershipAuthenticated, value.ok {
        output.status = "placed_receipts_required"
        output.message += "; geometry passed, but complete caller-held receipts are required for authoritative batch proof"
    }
    if verbose || !value.ok {
        output.batch = context.0
        output.proof = context.1
        output.snapshot = snapshot
    }
    return output
}

private func restoreFrontmostApplication(_ bundleIdentifier: String, timeout: TimeInterval = 2) -> Bool {
    guard let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
    ).first(where: { !$0.isTerminated }) else {
        return false
    }
    _ = application.activate(options: [.activateAllWindows])
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
}

private func prove(_ arguments: Arguments, store: StateStore) throws {
    let batchID = try arguments.required("--batch")
    let receipts = try arguments.stringMap("--receipts")
    let restoreFocus = arguments.flags.contains("--restore-focus")
    let initialBatch = try store.read { state -> BatchPlan? in
        guard let batch = state.batches.first(where: { $0.id == batchID }) else { return nil }
        for item in batch.items {
            guard let record = state.restores.first(where: { $0.reservationID == item.reservationID }) else { continue }
            guard let receipt = receipts[item.reservationID] else {
                throw WorkspaceError.usage("Missing lifecycle receipt for reservation \(item.reservationID)")
            }
            try authenticate(record, receipt: receipt)
        }
        return batch
    }
    guard let initialBatch else {
        emit(SimpleOutput(ok: false, status: "not_found", message: "Batch not found or expired"))
        exit(3)
    }
    let focusRestored: Bool
    if restoreFocus, let bundleIdentifier = initialBatch.baselineFrontmostBundleIdentifier {
        focusRestored = restoreFrontmostApplication(bundleIdentifier)
    } else {
        focusRestored = !restoreFocus || initialBatch.baselineFrontmostBundleIdentifier == nil
    }
    let snapshot = try desktopSnapshot()
    let context = try store.read { state -> (BatchPlan, BatchProof) in
        guard let batch = state.batches.first(where: { $0.id == batchID }) else {
            throw WorkspaceError.runtime("Batch disappeared while proving: \(batchID)")
        }
        return (batch, buildBatchProof(batch: batch, snapshot: snapshot, state: state, receipts: receipts))
    }
    let ok = context.1.ok && focusRestored
    emit(ProveOutput(
        ok: ok,
        status: ok ? "proved" : "proof_failed",
        batchID: batchID,
        focusRestored: focusRestored,
        batch: context.0,
        proof: context.1,
        snapshot: snapshot,
        message: ok
            ? "Batch placement, baseline geometry, display containment, disjointness, and focus are verified"
            : "One or more batch proof conditions failed"
    ))
    if !ok { exit(7) }
}

private func replanBatchForActualWindow(
    reservation: Reservation,
    window: WindowInfo,
    snapshot: DesktopSnapshot,
    store: StateStore
) throws -> BatchReplanResult {
    guard let batchID = reservation.batchID else {
        return BatchReplanResult(reservation: reservation, replanned: false, failureReason: nil)
    }
    return try store.withState { state in
        guard let batchIndex = state.batches.firstIndex(where: { $0.id == batchID }),
              let currentIndex = state.batches[batchIndex].items.firstIndex(where: { $0.reservationID == reservation.id }) else {
            throw WorkspaceError.runtime("Batch lifecycle state is missing for reservation: \(reservation.id)")
        }
        updateObservedGeometry(state: &state, app: reservation.app, launchSize: window.bounds.cgRect.size)
        state.batches[batchIndex].items[currentIndex].actualLaunchBounds = window.bounds
        state.batches[batchIndex].items[currentIndex].windowID = window.id
        state.batches[batchIndex].items[currentIndex].pid = window.pid
        state.batches[batchIndex].status = .active

        let currentPlanned = state.batches[batchIndex].items[currentIndex].plannedSize.cgSize
        guard abs(currentPlanned.width - window.bounds.width) > 4
                || abs(currentPlanned.height - window.bounds.height) > 4 else {
            return BatchReplanResult(reservation: reservation, replanned: false, failureReason: nil)
        }

        let pending = state.batches[batchIndex].items.enumerated().filter { $0.element.status == .planned }
        let resolved = pending.map { index, item -> ResolvedBatchItem in
            let size = index == currentIndex ? window.bounds.cgRect.size : item.plannedSize.cgSize
            let request = BatchRequestItem(
                app: item.app, width: size.width, height: size.height,
                launchWidth: size.width, launchHeight: size.height,
                minimumWidth: size.width, minimumHeight: size.height,
                resizable: item.resizable
            )
            let profile = WindowGeometryProfile(
                app: item.app, launchSize: SizeValue(size), minimumSize: SizeValue(size),
                resizable: item.resizable, source: item.geometrySource, observedAt: nil
            )
            return ResolvedBatchItem(requestIndex: index, request: request, plannedSize: size, profile: profile)
        }
        let pendingReservationIDs = Set(pending.map { $0.element.reservationID })
        guard let placements = solveBatchPlacements(
            items: resolved,
            snapshot: snapshot,
            reservations: state.reservations,
            ignoringWindowIDs: [window.id],
            ignoringReservationIDs: pendingReservationIDs,
            layoutVariant: state.batches[batchIndex].layoutVariant ?? 0
        ) else {
            let reason = "Actual \(reservation.app) launch bounds \(Int(window.bounds.width))x\(Int(window.bounds.height)) leave no safe layout for the remaining batch"
            state.batches[batchIndex].status = .failed
            state.batches[batchIndex].failureReason = reason
            state.batches[batchIndex].items[currentIndex].status = .failed
            state.reservations.removeAll { pendingReservationIDs.contains($0.id) }
            return BatchReplanResult(reservation: reservation, replanned: true, failureReason: reason)
        }

        let placementByIndex = Dictionary(uniqueKeysWithValues: placements.map { ($0.requestIndex, $0) })
        for (index, _) in pending {
            guard let placement = placementByIndex[index] else { continue }
            state.batches[batchIndex].items[index].plannedSize = SizeValue(placement.region.size)
            state.batches[batchIndex].items[index].targetDisplayID = placement.display.id
            state.batches[batchIndex].items[index].region = Rect(placement.region)
            if let reservationIndex = state.reservations.firstIndex(where: {
                $0.id == state.batches[batchIndex].items[index].reservationID
            }) {
                state.reservations[reservationIndex].targetDisplayID = placement.display.id
                state.reservations[reservationIndex].region = Rect(placement.region)
            }
        }
        guard let updated = state.reservations.first(where: { $0.id == reservation.id }) else {
            throw WorkspaceError.runtime("Current reservation disappeared during batch replanning")
        }
        return BatchReplanResult(reservation: updated, replanned: true, failureReason: nil)
    }
}

private func markBatchItem(
    reservationID: String,
    status: BatchItemStatus,
    failureReason: String? = nil,
    window: WindowInfo? = nil,
    finalBounds: Rect? = nil,
    removeReservation: Bool = false,
    store: StateStore
) throws {
    try store.withState { state in
        guard let reservation = state.reservations.first(where: { $0.id == reservationID }),
              let batchID = reservation.batchID,
              let batchIndex = state.batches.firstIndex(where: { $0.id == batchID }),
              let itemIndex = state.batches[batchIndex].items.firstIndex(where: { $0.reservationID == reservationID }) else {
            return
        }
        state.batches[batchIndex].items[itemIndex].status = status
        if let window {
            state.batches[batchIndex].items[itemIndex].windowID = window.id
            state.batches[batchIndex].items[itemIndex].pid = window.pid
        }
        if let finalBounds {
            state.batches[batchIndex].items[itemIndex].finalBounds = finalBounds
        }
        if let failureReason {
            state.batches[batchIndex].status = .failed
            state.batches[batchIndex].failureReason = failureReason
            let remainingIDs = Set(state.batches[batchIndex].items.filter { $0.status == .planned }.map(\.reservationID))
            state.reservations.removeAll { remainingIDs.contains($0.id) }
        } else if state.batches[batchIndex].items.allSatisfy({ $0.status == .placed }) {
            state.batches[batchIndex].status = .completed
        } else {
            state.batches[batchIndex].status = .active
        }
        if removeReservation {
            state.reservations.removeAll { $0.id == reservationID }
        }
    }
}

private func prepare(_ arguments: Arguments, store: StateStore) throws {
    let app = try arguments.required("--app")
    let width = try arguments.double("--width", default: 900)
    let height = try arguments.double("--height", default: 700)
    let ttl = try arguments.double("--ttl", default: 90)
    let dryRun = arguments.flags.contains("--dry-run")
    let snapshot = try desktopSnapshot()
    let appWasRunning = NSRunningApplication.runningApplications(withBundleIdentifier: app)
        .contains { !$0.isTerminated }
    let now = Date().timeIntervalSince1970

    let output: PrepareOutput = try store.withState { state in
        let request = BatchRequestItem(
            app: app, width: width, height: height,
            launchWidth: nil, launchHeight: nil,
            minimumWidth: nil, minimumHeight: nil, resizable: nil
        )
        let profile = resolvedGeometry(for: request, cachedProfiles: state.geometryProfiles)
        let requestedPlan = profile.map { plannedSize(for: request, profile: $0) }
            ?? CGSize(width: width, height: height)
        guard let choice = choosePlacement(
            snapshot: snapshot,
            reservations: state.reservations,
            desiredWidth: requestedPlan.width,
            desiredHeight: requestedPlan.height,
            minimumWidth: requestedPlan.width,
            minimumHeight: requestedPlan.height
        ) else {
            return PrepareOutput(
                ok: false,
                status: "no_safe_placement",
                reservationID: nil,
                app: app,
                protectedDisplayID: snapshot.focusedDisplayID,
                targetDisplayID: nil,
                region: nil,
                expiresAt: nil,
                appWasRunning: appWasRunning,
                plannedSize: SizeValue(requestedPlan),
                geometrySource: profile?.source ?? "unknown",
                geometryCertain: profile != nil,
                resizable: profile?.resizable,
                dryRun: dryRun,
                message: "No unoccupied region fits the planned window geometry"
            )
        }
        let id = UUID().uuidString.lowercased()
        let expiration = now + ttl
        if !dryRun {
            state.reservations.append(Reservation(
                id: id,
                app: app,
                createdAt: now,
                expiresAt: expiration,
                protectedDisplayID: snapshot.focusedDisplayID,
                targetDisplayID: choice.display.id,
                region: Rect(choice.region),
                baselineWindowIDs: snapshot.windows.filter { $0.bundleIdentifier == app }.map(\.id),
                appWasRunning: appWasRunning,
                batchID: nil
            ))
        }
        return PrepareOutput(
            ok: true,
            status: dryRun ? "dry_run" : (profile == nil ? "reserved_uncertain" : "reserved"),
            reservationID: dryRun ? nil : id,
            app: app,
            protectedDisplayID: snapshot.focusedDisplayID,
            targetDisplayID: choice.display.id,
            region: Rect(choice.region),
            expiresAt: dryRun ? nil : expiration,
            appWasRunning: appWasRunning,
            plannedSize: SizeValue(requestedPlan),
            geometrySource: profile?.source ?? "unknown",
            geometryCertain: profile != nil,
            resizable: profile?.resizable,
            dryRun: dryRun,
            message: dryRun
                ? "Safe placement found; nothing was reserved or moved"
                : (profile == nil
                    ? "Safe requested-size placement reserved with explicit launch-geometry uncertainty"
                    : "Safe placement reserved from bounded application geometry")
        )
    }
    emit(output)
    if !output.ok { exit(3) }
}

private func place(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    commandLifecycleReceipts = try arguments.optionalStringMap("--receipts")
    let wait = try arguments.double("--wait", default: 6)
    let verbose = arguments.flags.contains("--verbose")
    var reservation = try store.read { state -> Reservation in
        guard let value = state.reservations.first(where: { $0.id == reservationID }) else {
            throw WorkspaceError.runtime("Reservation not found or expired: \(reservationID)")
        }
        return value
    }

    let targetResult = try waitForUniqueTargetWindow(reservation: reservation, timeout: wait)
    let snapshot = targetResult.snapshot
    guard case .unique(let window) = targetResult.match else {
        let ambiguousWindowIDs: [UInt32]
        if case .ambiguous(let candidates) = targetResult.match {
            ambiguousWindowIDs = candidates.map(\.id)
        } else {
            ambiguousWindowIDs = []
        }
        let isAmbiguous = !ambiguousWindowIDs.isEmpty
        let reason = isAmbiguous
            ? "Multiple new target-app windows appeared; ownership is ambiguous for window IDs \(ambiguousWindowIDs)"
            : "No stable new target-app window appeared before the placement deadline"
        try markBatchItem(
            reservationID: reservationID,
            status: .failed,
            failureReason: reason,
            store: store
        )
        emit(try enrichedPlaceOutput(ActionOutput(
            ok: false, status: isAmbiguous ? "ambiguous_new_windows" : "no_new_window",
            reservationID: reservationID, app: reservation.app,
            windowID: nil, originalBounds: nil, currentBounds: nil, targetRegion: reservation.region,
            computerUseDrag: nil, message: reason + "; no window was moved or recorded as task-owned"
        ), reservationID: reservationID, store: store))
        exit(4)
    }

    let original = window.bounds.cgRect
    var replannedForActualBounds = false
    if reservation.batchID != nil {
        let result = try replanBatchForActualWindow(
            reservation: reservation,
            window: window,
            snapshot: snapshot,
            store: store
        )
        reservation = result.reservation
        replannedForActualBounds = result.replanned
        if let failureReason = result.failureReason {
            let owned = try makeOwnedRestoreRecord(
                reservation: reservation,
                window: window,
                originalBounds: original
            )
            try store.withState { state in
                state.restores.removeAll { $0.reservationID == reservationID }
                state.restores.append(owned.record)
            }
            emit(try enrichedPlaceOutput(ActionOutput(
                ok: false, status: "batch_replan_failed",
                reservationID: reservationID, app: reservation.app,
                windowID: window.id, originalBounds: Rect(original), currentBounds: Rect(original),
                targetRegion: reservation.region, computerUseDrag: nil,
                lifecycleReceipt: owned.receipt,
                message: failureReason + "; stop before launching another batch application"
            ), reservationID: reservationID, store: store))
            exit(10)
        }
    } else if original.width > reservation.region.width || original.height > reservation.region.height {
        let activeReservations = try store.read { $0.reservations }
        if let choice = choosePlacement(
            snapshot: snapshot,
            reservations: activeReservations,
            desiredWidth: original.width,
            desiredHeight: original.height,
            minimumWidth: original.width,
            minimumHeight: original.height,
            ignoringWindowIDs: [window.id],
            ignoringReservationIDs: [reservationID]
        ) {
            reservation.targetDisplayID = choice.display.id
            reservation.region = Rect(choice.region)
            replannedForActualBounds = true
            try store.withState { state in
                guard let index = state.reservations.firstIndex(where: { $0.id == reservationID }) else {
                    throw WorkspaceError.runtime("Reservation disappeared while replanning: \(reservationID)")
                }
                state.reservations[index] = reservation
            }
        }
        try store.withState { state in
            updateObservedGeometry(state: &state, app: reservation.app, launchSize: original.size)
        }
    }
    let target = desiredBounds(for: window, region: reservation.region)
    let owned = try makeOwnedRestoreRecord(
        reservation: reservation,
        window: window,
        originalBounds: original
    )
    let restore = owned.record
    let lifecycleReceipt = owned.receipt
    try store.withState { state in
        state.restores.removeAll { $0.reservationID == reservationID }
        state.restores.append(restore)
    }

    let requiresResize = target.width < original.width || target.height < original.height
    if requiresResize {
        let resizeAllowed = try store.read { state -> Bool in
            if let batchID = reservation.batchID,
               let batch = state.batches.first(where: { $0.id == batchID }),
               let item = batch.items.first(where: { $0.reservationID == reservationID }),
               item.resizable == true {
                return true
            }
            let request = BatchRequestItem(
                app: reservation.app,
                width: target.width,
                height: target.height,
                launchWidth: nil,
                launchHeight: nil,
                minimumWidth: nil,
                minimumHeight: nil,
                resizable: nil
            )
            guard let profile = resolvedGeometry(for: request, cachedProfiles: state.geometryProfiles) else {
                return false
            }
            return profile.resizable == true
                && target.width >= profile.minimumSize.width
                && target.height >= profile.minimumSize.height
        }
        if !resizeAllowed {
            let reason = "The recorded application geometry does not prove that this window can be resized to the reserved target"
            try markBatchItem(reservationID: reservationID, status: .failed, failureReason: reason, store: store)
            emit(try enrichedPlaceOutput(ActionOutput(
                ok: false, status: "unresizable_target",
                reservationID: reservationID, app: reservation.app,
                windowID: window.id, originalBounds: Rect(original), currentBounds: Rect(original),
                targetRegion: reservation.region, computerUseDrag: nil,
                lifecycleReceipt: lifecycleReceipt,
                message: reason + "; no resize drag was returned"
            ), reservationID: reservationID, store: store))
            exit(10)
        }
    }

    let axMatch = AXIsProcessTrusted()
        ? findAXWindow(pid: window.pid, matching: original)
        : AXWindowMatch.none
    if case .ambiguous = axMatch {
        let reason = "More than one Accessibility window matches the target bounds; no window was moved"
        try markBatchItem(reservationID: reservationID, status: .failed, failureReason: reason, store: store)
        emit(try enrichedPlaceOutput(ActionOutput(
            ok: false, status: "ambiguous_ax_window", reservationID: reservationID, app: reservation.app,
            windowID: window.id, originalBounds: Rect(original), currentBounds: Rect(original),
            targetRegion: reservation.region, computerUseDrag: nil,
            lifecycleReceipt: lifecycleReceipt, message: reason
        ), reservationID: reservationID, store: store))
        exit(10)
    }

    if case .unique(let axWindow) = axMatch {
        let result = setAXBounds(axWindow, rect: target)
        if result == .success {
            let updated = try waitForSettledWindow(id: window.id, pid: window.pid, target: target)
            let settled = updated.map { bounds in
                reservation.region.cgRect.insetBy(dx: -8, dy: -8).contains(bounds.cgRect)
            } == true
            if settled {
                try markBatchItem(
                    reservationID: reservationID,
                    status: .placed,
                    window: window,
                    finalBounds: updated,
                    removeReservation: true,
                    store: store
                )
                emit(try enrichedPlaceOutput(ActionOutput(
                    ok: true, status: "placed",
                    reservationID: reservationID, app: reservation.app,
                    windowID: window.id, originalBounds: Rect(original), currentBounds: updated,
                    targetRegion: reservation.region, computerUseDrag: nil,
                    lifecycleReceipt: lifecycleReceipt,
                    message: replannedForActualBounds
                        ? "Window replanned for its actual bounds, placed, and verified through macOS Accessibility"
                        : "Window placed and verified through macOS Accessibility"
                ), reservationID: reservationID, verbose: verbose, store: store))
                return
            }

            if requiresResize,
               setAXBounds(axWindow, rect: original) == .success,
               let restored = try waitForSettledWindow(id: window.id, pid: window.pid, target: original),
               boundsDelta(restored.cgRect, original) <= 4 {
                emit(try enrichedPlaceOutput(ActionOutput(
                    ok: false, status: "computer_use_drags_required",
                    reservationID: reservationID, app: reservation.app,
                    windowID: window.id, originalBounds: Rect(original), currentBounds: restored,
                    targetRegion: reservation.region, computerUseDrag: nil,
                    computerUseDrags: resizeThenMovePlans(app: reservation.app, from: original, to: target),
                    lifecycleReceipt: lifecycleReceipt,
                    message: "Accessibility could not resize the window; execute the returned resize and move drags in order with Computer Use, then run verify"
                ), reservationID: reservationID, store: store))
                exit(5)
            }

            emit(try enrichedPlaceOutput(ActionOutput(
                ok: false, status: "placement_unsettled",
                reservationID: reservationID, app: reservation.app,
                windowID: window.id, originalBounds: Rect(original), currentBounds: updated,
                targetRegion: reservation.region, computerUseDrag: nil,
                lifecycleReceipt: lifecycleReceipt,
                message: "Accessibility accepted the move, but the window server did not settle inside the reservation"
            ), reservationID: reservationID, store: store))
            try markBatchItem(
                reservationID: reservationID,
                status: .failed,
                failureReason: "Accessibility placement did not settle inside the batch reservation",
                store: store
            )
            exit(7)
        }
    }

    if target.width < original.width || target.height < original.height {
        emit(try enrichedPlaceOutput(ActionOutput(
            ok: false, status: "computer_use_drags_required", reservationID: reservationID, app: reservation.app,
            windowID: window.id, originalBounds: Rect(original), currentBounds: Rect(original),
            targetRegion: reservation.region, computerUseDrag: nil,
            computerUseDrags: resizeThenMovePlans(app: reservation.app, from: original, to: target),
            lifecycleReceipt: lifecycleReceipt,
            message: "Direct Accessibility resize is unavailable; execute the returned resize and move drags in order with Computer Use, then run verify"
        ), reservationID: reservationID, store: store))
        exit(5)
    }

    emit(try enrichedPlaceOutput(ActionOutput(
        ok: false, status: "computer_use_drag_required", reservationID: reservationID, app: reservation.app,
        windowID: window.id, originalBounds: Rect(original), currentBounds: Rect(original),
        targetRegion: reservation.region, computerUseDrag: dragPlan(app: reservation.app, from: original, to: target),
        lifecycleReceipt: lifecycleReceipt,
        message: "Direct Accessibility placement is unavailable; execute the returned drag with Computer Use, then run verify"
    ), reservationID: reservationID, store: store))
    exit(5)
}

private func verify(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let receipt = try arguments.required("--receipt")
    commandLifecycleReceipts = try arguments.optionalStringMap("--receipts")
    commandLifecycleReceipts[reservationID] = receipt
    let verbose = arguments.flags.contains("--verbose")
    let pair = try store.read { state -> (Reservation?, RestoreRecord?) in
        (state.reservations.first { $0.id == reservationID }, state.restores.first { $0.reservationID == reservationID })
    }
    guard let record = pair.1 else {
        throw WorkspaceError.runtime("Restore record not found for reservation: \(reservationID)")
    }
    try authenticate(record, receipt: receipt)
    let snapshot = try desktopSnapshot()
    guard let window = snapshot.windows.first(where: { $0.id == record.windowID && $0.pid == record.pid }) else {
        emit(ActionOutput(
            ok: false, status: "window_not_found", reservationID: reservationID, app: record.app,
            windowID: record.windowID, originalBounds: record.originalBounds, currentBounds: nil,
            targetRegion: record.targetRegion, computerUseDrag: nil, message: "The placed window is no longer available"
        ))
        exit(6)
    }
    let current = window.bounds.cgRect
    let target = record.targetRegion.cgRect
    let tolerance: CGFloat = 8
    let targetWithTolerance = target.insetBy(dx: -tolerance, dy: -tolerance)
    let isInside = targetWithTolerance.contains(current)
    if isInside {
        try markBatchItem(
            reservationID: reservationID,
            status: .placed,
            window: window,
            finalBounds: Rect(current),
            removeReservation: true,
            store: store
        )
    } else {
        if record.originalBounds.width > record.targetRegion.width
            || record.originalBounds.height > record.targetRegion.height {
            try store.withState { state in
                updateObservedGeometry(
                    state: &state,
                    app: record.app,
                    launchSize: record.originalBounds.cgRect.size,
                    resizable: false
                )
            }
        }
        try markBatchItem(
            reservationID: reservationID,
            status: .failed,
            failureReason: "The placed window remained outside its batch reservation",
            store: store
        )
    }
    emit(try enrichedPlaceOutput(ActionOutput(
        ok: isInside, status: isInside ? "verified" : "verification_failed", reservationID: reservationID,
        app: record.app, windowID: record.windowID, originalBounds: record.originalBounds,
        currentBounds: Rect(current), targetRegion: record.targetRegion, computerUseDrag: nil,
        message: isInside ? "Window is inside the reserved region" : "Window is outside the reserved region"
    ), reservationID: reservationID, verbose: verbose, store: store))
    if !isInside { exit(7) }
}

private func restore(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let receipt = try arguments.required("--receipt")
    let record = try store.read { state -> RestoreRecord in
        guard let value = state.restores.first(where: { $0.reservationID == reservationID }) else {
            throw WorkspaceError.runtime("Restore record not found: \(reservationID)")
        }
        return value
    }
    try authenticate(record, receipt: receipt)
    let snapshot = try desktopSnapshot()
    guard let window = snapshot.windows.first(where: { $0.id == record.windowID && $0.pid == record.pid }) else {
        throw WorkspaceError.runtime("The original window is no longer available")
    }
    let current = window.bounds.cgRect
    let axMatch = AXIsProcessTrusted()
        ? findAXWindow(pid: window.pid, matching: current)
        : AXWindowMatch.none
    if case .ambiguous = axMatch {
        emit(ActionOutput(
            ok: false, status: "ambiguous_ax_window", reservationID: reservationID, app: record.app,
            windowID: record.windowID, originalBounds: record.originalBounds, currentBounds: Rect(current),
            targetRegion: record.targetRegion, computerUseDrag: nil,
            message: "More than one Accessibility window matches the recorded bounds; no window was restored"
        ))
        exit(10)
    }
    if case .unique(let axWindow) = axMatch,
       setAXBounds(axWindow, rect: record.originalBounds.cgRect) == .success {
        try store.withState { state in
            state.restores.removeAll { $0.reservationID == reservationID }
            state.reservations.removeAll { $0.id == reservationID }
        }
        emit(ActionOutput(
            ok: true, status: "restored", reservationID: reservationID, app: record.app,
            windowID: record.windowID, originalBounds: record.originalBounds, currentBounds: record.originalBounds,
            targetRegion: record.targetRegion, computerUseDrag: nil,
            message: "Window restored through macOS Accessibility"
        ))
        return
    }
    emit(ActionOutput(
        ok: false, status: "computer_use_drag_required", reservationID: reservationID, app: record.app,
        windowID: record.windowID, originalBounds: record.originalBounds, currentBounds: Rect(current),
        targetRegion: record.targetRegion,
        computerUseDrag: dragPlan(app: record.app, from: current, to: record.originalBounds.cgRect),
        message: "Direct Accessibility restore is unavailable; execute the returned drag with Computer Use"
    ))
    exit(5)
}

private func finish(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let receipt = try arguments.required("--receipt")
    let apply = arguments.flags.contains("--apply")
    let leaveOpen = arguments.flags.contains("--leave-open")
    let confirmClosed = arguments.flags.contains("--confirm-closed")
    if confirmClosed && (apply || leaveOpen) {
        throw WorkspaceError.usage("--confirm-closed cannot be combined with --apply or --leave-open")
    }

    let record = try store.read { state -> RestoreRecord in
        guard let value = state.restores.first(where: { $0.reservationID == reservationID }) else {
            throw WorkspaceError.runtime("Lifecycle record not found: \(reservationID)")
        }
        return value
    }
    try authenticate(record, receipt: receipt)

    if confirmClosed {
        guard exactWindowInfo(id: record.windowID, pid: record.pid) == nil else {
            emit(FinishOutput(
                ok: false, status: "cleanup_not_complete", reservationID: reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: nil,
                plannedAction: record.appWasRunning ? .closeCreatedWindow : .closeWindowThenQuit,
                applied: false, appTerminated: nil, message: "The task-owned window is still open"
            ))
            exit(9)
        }
        var appTerminated: Bool?
        if !record.appWasRunning {
            let hasOtherWindows = try desktopSnapshot().windows.contains { $0.bundleIdentifier == record.app }
            if !hasOtherWindows { appTerminated = gracefullyTerminate(pid: record.pid) }
        }
        try store.withState { state in
            state.restores.removeAll { $0.reservationID == reservationID }
            state.reservations.removeAll { $0.id == reservationID }
        }
        emit(FinishOutput(
            ok: true, status: "cleanup_verified", reservationID: reservationID,
            app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: false, safety: nil, plannedAction: .alreadyClosed,
            applied: true, appTerminated: appTerminated,
            message: "Task-owned window closure verified and lifecycle state finalized"
        ))
        return
    }

    let result = try finishRecord(record, apply: apply, leaveOpen: leaveOpen, store: store)
    emit(result)
    if !result.ok { exit(result.status == "computer_use_close_required" ? 5 : 9) }
}


private func finishRecord(
    _ record: RestoreRecord,
    apply: Bool,
    leaveOpen: Bool,
    store: StateStore
) throws -> FinishOutput {
    func finalize() throws {
        try store.withState { state in
            state.restores.removeAll { $0.reservationID == record.reservationID }
            state.reservations.removeAll { $0.id == record.reservationID }
        }
    }

    var snapshot = try desktopSnapshot()
    var window = snapshot.windows.first { $0.id == record.windowID && $0.pid == record.pid }
    let axMatch: AXWindowMatch = window.map { value in
        AXIsProcessTrusted() ? findAXWindow(pid: value.pid, matching: value.bounds.cgRect) : .none
    } ?? .none
    if case .ambiguous = axMatch {
        return FinishOutput(
            ok: false, status: "ambiguous_ax_window", reservationID: record.reservationID,
            app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: window != nil, safety: nil,
            plannedAction: record.appWasRunning ? .closeCreatedWindow : .closeWindowThenQuit,
            applied: false, appTerminated: nil,
            message: "More than one Accessibility window matches the recorded bounds; cleanup preserved every window"
        )
    }
    let axWindow: AXUIElement?
    if case .unique(let element) = axMatch { axWindow = element } else { axWindow = nil }
    let safety = axWindow.map(windowSafety)
    let action = cleanupAction(
        appWasRunning: record.appWasRunning,
        windowPresent: window != nil,
        safety: safety,
        leaveOpen: leaveOpen
    )

    if !apply {
        return FinishOutput(
            ok: true, status: "cleanup_plan", reservationID: record.reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: window != nil, safety: safety, plannedAction: action,
            applied: false, appTerminated: nil, message: "Cleanup plan ready for batch review"
        )
    }

    switch action {
    case .leaveOpen:
        try finalize()
        return FinishOutput(
            ok: true, status: "left_open", reservationID: record.reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: window != nil, safety: safety, plannedAction: action,
            applied: true, appTerminated: nil,
            message: "Task-owned window intentionally left open and lifecycle state finalized"
        )

    case .preserveEdited, .preserveModal:
        return FinishOutput(
            ok: true,
            status: action == .preserveEdited ? "preserved_edited" : "preserved_modal",
            reservationID: record.reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: true, safety: safety, plannedAction: action,
            applied: false, appTerminated: nil,
            message: action == .preserveEdited
                ? "Window reports edited content and was preserved"
                : "Window has a modal surface or sheet and was preserved"
        )

    case .alreadyClosed:
        var appTerminated: Bool?
        if !record.appWasRunning && snapshot.windows.allSatisfy({ $0.bundleIdentifier != record.app }) {
            appTerminated = gracefullyTerminate(pid: record.pid)
        }
        try finalize()
        return FinishOutput(
            ok: true, status: "already_closed", reservationID: record.reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: false, safety: safety, plannedAction: action,
            applied: true, appTerminated: appTerminated,
            message: "Task-owned window was already closed; lifecycle state finalized"
        )

    case .closeCreatedWindow, .closeWindowThenQuit:
        guard let axWindow, safety?.hasCloseButton == true else {
            return FinishOutput(
                ok: false, status: "computer_use_close_required", reservationID: record.reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: safety, plannedAction: action,
                applied: false, appTerminated: nil,
                message: "Direct close is unavailable; close the exact task-owned window with Computer Use"
            )
        }
        guard closeAXWindow(axWindow) == .success else {
            return FinishOutput(
                ok: false, status: "computer_use_close_required", reservationID: record.reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: safety, plannedAction: action,
                applied: false, appTerminated: nil,
                message: "macOS rejected the direct close; close the exact task-owned window with Computer Use"
            )
        }
        guard try waitForWindowToClose(id: record.windowID, pid: record.pid) else {
            return FinishOutput(
                ok: false, status: "cleanup_pending", reservationID: record.reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: safety, plannedAction: action,
                applied: false, appTerminated: nil,
                message: "Close was requested, but the window remains open"
            )
        }
        snapshot = try desktopSnapshot()
        window = snapshot.windows.first { $0.id == record.windowID && $0.pid == record.pid }
        var appTerminated: Bool?
        var message = "Task-owned window closed"
        if action == .closeWindowThenQuit {
            let hasOtherWindows = snapshot.windows.contains { $0.bundleIdentifier == record.app }
            if hasOtherWindows {
                appTerminated = false
                message += "; app retained because another window remains"
            } else {
                appTerminated = gracefullyTerminate(pid: record.pid)
                message += appTerminated == true ? "; agent-launched app quit" : "; app did not quit"
            }
        }
        try finalize()
        return FinishOutput(
            ok: true, status: "cleaned_up", reservationID: record.reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: window != nil, safety: safety, plannedAction: action,
            applied: true, appTerminated: appTerminated, message: message
        )
    }
}

private func finishBatch(_ arguments: Arguments, store: StateStore) throws {
    let batchID = try arguments.required("--batch")
    let receipts = try arguments.stringMap("--receipts")
    let apply = arguments.flags.contains("--apply")
    let leaveOpen = arguments.flags.contains("--leave-open")
    let context = try store.read { state -> (BatchPlan, [String: RestoreRecord]) in
        guard let batch = state.batches.first(where: { $0.id == batchID }) else {
            throw WorkspaceError.runtime("Batch not found or expired: \(batchID)")
        }
        let reservationIDs = Set(batch.items.map(\.reservationID))
        let records = state.restores.filter { reservationIDs.contains($0.reservationID) }
        return (batch, Dictionary(uniqueKeysWithValues: records.map { ($0.reservationID, $0) }))
    }
    for record in context.1.values {
        guard let receipt = receipts[record.reservationID] else {
            throw WorkspaceError.usage("Missing lifecycle receipt for reservation \(record.reservationID)")
        }
        try authenticate(record, receipt: receipt)
    }

    if apply && leaveOpen {
        let snapshot = try desktopSnapshot()
        let recordIDs = Set(context.1.keys)
        try store.withState { state in
            state.restores.removeAll { recordIDs.contains($0.reservationID) }
            state.reservations.removeAll { $0.batchID == batchID }
        }
        let items = context.0.items.map { item -> BatchFinishItemOutput in
            guard let record = context.1[item.reservationID] else {
                return BatchFinishItemOutput(
                    app: item.app, reservationID: item.reservationID, result: nil,
                    status: "unused_released", applied: true,
                    message: "Unused reservation released"
                )
            }
            let present = snapshot.windows.contains { $0.id == record.windowID && $0.pid == record.pid }
            let result = FinishOutput(
                ok: true, status: "left_open", reservationID: record.reservationID, app: record.app,
                appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: present, safety: nil, plannedAction: .leaveOpen,
                applied: true, appTerminated: nil,
                message: "Task-owned window intentionally left open and lifecycle state finalized"
            )
            return BatchFinishItemOutput(
                app: item.app, reservationID: item.reservationID, result: result,
                status: result.status, applied: true, message: result.message
            )
        }
        emit(BatchFinishOutput(
            ok: true, status: "batch_finalized", batchID: batchID,
            applied: true, leaveOpen: true, items: items,
            message: "Batch cleanup plans reviewed and all lifecycle records finalized in one transaction"
        ))
        return
    }

    var items: [BatchFinishItemOutput] = []
    var unusedReservationIDs: Set<String> = []
    for item in context.0.items {
        guard let record = context.1[item.reservationID] else {
            unusedReservationIDs.insert(item.reservationID)
            items.append(BatchFinishItemOutput(
                app: item.app, reservationID: item.reservationID, result: nil,
                status: apply ? "unused_released" : "unused_release_planned",
                applied: apply,
                message: apply ? "Unused reservation released" : "Unused reservation will be released"
            ))
            continue
        }
        let result = try finishRecord(record, apply: apply, leaveOpen: leaveOpen, store: store)
        items.append(BatchFinishItemOutput(
            app: item.app, reservationID: item.reservationID, result: result,
            status: result.status, applied: result.applied, message: result.message
        ))
    }
    if apply && !unusedReservationIDs.isEmpty {
        try store.withState { state in
            state.reservations.removeAll { unusedReservationIDs.contains($0.id) }
        }
    }
    let ok = items.allSatisfy { $0.result?.ok ?? true }
    emit(BatchFinishOutput(
        ok: ok, status: ok ? (apply ? "batch_finalized" : "batch_cleanup_plan") : "batch_cleanup_incomplete",
        batchID: batchID, applied: apply, leaveOpen: leaveOpen, items: items,
        message: apply ? "Batch cleanup processing finished" : "Batch cleanup plan ready for review"
    ))
    if !ok { exit(9) }
}

private func release(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let removed = try store.withState { state -> Bool in
        let count = state.reservations.count
        state.reservations.removeAll { $0.id == reservationID }
        return state.reservations.count != count
    }
    emit(SimpleOutput(
        ok: removed,
        status: removed ? "released" : "not_found",
        message: removed ? "Reservation released" : "Reservation was already absent or expired"
    ))
}

private func runSelfTests() {
    var failures: [String] = []
    var checkCount = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        checkCount += 1
        if !condition() { failures.append(name) }
    }

    let left = DisplayInfo(
        id: 1,
        frame: Rect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: Rect(x: 0, y: 24, width: 1440, height: 852),
        isMain: true
    )
    let right = DisplayInfo(
        id: 2,
        frame: Rect(x: 1440, y: 0, width: 1920, height: 1080),
        visibleFrame: Rect(x: 1440, y: 24, width: 1920, height: 1056),
        isMain: false
    )
    let base = DesktopSnapshot(
        capturedAt: 0,
        accessibilityTrusted: true,
        frontmostBundleIdentifier: "com.openai.chat",
        focusedDisplayID: 1,
        pointerDisplayID: 1,
        displays: [left, right],
        windows: [WindowInfo(id: 10, pid: 10, bundleIdentifier: "com.openai.chat", bounds: left.visibleFrame, layer: 0)]
    )
    let first = choosePlacement(snapshot: base, reservations: [], desiredWidth: 900, desiredHeight: 700)
    check(first?.display.id == 2, "prefers the non-focused display")
    check(first.map { right.visibleFrame.cgRect.contains($0.region) } == true, "stays inside visible bounds")

    if let first {
        let reservation = Reservation(
            id: "one", app: "com.apple.TextEdit", createdAt: 0, expiresAt: 100,
            protectedDisplayID: 1, targetDisplayID: 2, region: Rect(first.region),
            baselineWindowIDs: [], appWasRunning: false
        )
        let second = choosePlacement(snapshot: base, reservations: [reservation], desiredWidth: 900, desiredHeight: 700)
        check(second?.display.id == 2, "keeps concurrent placement off the focused display")
        check(second.map { !$0.region.intersects(first.region) } == true, "does not overlap a live reservation")
    }

    let single = DesktopSnapshot(
        capturedAt: 0,
        accessibilityTrusted: true,
        frontmostBundleIdentifier: "com.openai.chat",
        focusedDisplayID: 1,
        pointerDisplayID: 1,
        displays: [left],
        windows: [WindowInfo(
            id: 11, pid: 10, bundleIdentifier: "com.openai.chat",
            bounds: Rect(x: 0, y: 24, width: 700, height: 852), layer: 0
        )]
    )
    let singleChoice = choosePlacement(snapshot: single, reservations: [], desiredWidth: 600, desiredHeight: 600)
    check(singleChoice?.display.id == 1, "supports a single display")
    check(singleChoice.map { !$0.region.intersects(single.windows[0].bounds.cgRect) } == true, "avoids the focused window")

    let focusedFallback = DesktopSnapshot(
        capturedAt: 0,
        accessibilityTrusted: true,
        frontmostBundleIdentifier: "com.openai.chat",
        focusedDisplayID: 1,
        pointerDisplayID: 1,
        displays: [left, right],
        windows: [
            WindowInfo(
                id: 12, pid: 10, bundleIdentifier: "com.openai.chat",
                bounds: Rect(x: 0, y: 24, width: 700, height: 852), layer: 0
            ),
            WindowInfo(id: 13, pid: 13, bundleIdentifier: "example.full", bounds: right.visibleFrame, layer: 0)
        ]
    )
    let fallbackChoice = choosePlacement(
        snapshot: focusedFallback,
        reservations: [],
        desiredWidth: 600,
        desiredHeight: 600
    )
    check(fallbackChoice?.display.id == 1, "uses safe space on the focused display when other displays are full")
    check(fallbackChoice.map { !$0.region.intersects(focusedFallback.windows[0].bounds.cgRect) } == true,
          "keeps focused-display placement clear of the active window")

    let fullyOccupied = DesktopSnapshot(
        capturedAt: 0,
        accessibilityTrusted: true,
        frontmostBundleIdentifier: "com.openai.chat",
        focusedDisplayID: 1,
        pointerDisplayID: 1,
        displays: [left, right],
        windows: [
            WindowInfo(id: 14, pid: 10, bundleIdentifier: "com.openai.chat", bounds: left.visibleFrame, layer: 0),
            WindowInfo(id: 15, pid: 15, bundleIdentifier: "example.full", bounds: right.visibleFrame, layer: 0)
        ]
    )
    check(choosePlacement(snapshot: fullyOccupied, reservations: [], desiredWidth: 900, desiredHeight: 700) == nil,
          "returns no safe placement when every display is occupied")

    let ignoredTarget = WindowInfo(
        id: 16, pid: 16, bundleIdentifier: "com.apple.Dictionary",
        bounds: Rect(x: 1500, y: 100, width: 690, height: 624), layer: 0
    )
    var replanSnapshot = base
    replanSnapshot.windows.append(ignoredTarget)
    let exactReplan = choosePlacement(
        snapshot: replanSnapshot,
        reservations: [],
        desiredWidth: 690,
        desiredHeight: 624,
        minimumWidth: 690,
        minimumHeight: 624,
        ignoringWindowIDs: [ignoredTarget.id]
    )
    check(exactReplan?.display.id == 2, "replans from a launched window's actual size")
    check(exactReplan?.region.size == CGSize(width: 690, height: 624), "keeps exact bounds during post-launch replanning")

    let fallbackDrags = resizeThenMovePlans(
        app: "com.apple.Dictionary",
        from: CGRect(x: 1095, y: 271, width: 690, height: 624),
        to: CGRect(x: 1770, y: 1653, width: 514, height: 520)
    )
    check(fallbackDrags.map(\.purpose) == ["resize", "move"], "returns ordered resize and move fallback drags")
    check(fallbackDrags.allSatisfy { $0.coordinateSpace == "app_local" }, "labels every fallback drag as app-local")
    check(fallbackDrags[0].from == PointValue(x: 687, y: 621), "starts resize at the app-local lower corner")
    check(fallbackDrags[0].to == PointValue(x: 511, y: 517), "resizes with app-local coordinates")
    check(fallbackDrags[1].from == PointValue(x: 257, y: 18), "starts move from an app-local title-bar point")
    check(fallbackDrags[1].to == PointValue(x: 932, y: 1400), "translates the global move delta into app-local coordinates")
    check(fallbackDrags[1].windowOrigin == PointValue(x: 1095, y: 271), "records the window origin used for coordinate validation")

    let fontRequest = BatchRequestItem(
        app: "com.apple.FontBook", width: 680, height: 520,
        launchWidth: nil, launchHeight: nil, minimumWidth: nil, minimumHeight: nil, resizable: nil
    )
    let fontProfile = resolvedGeometry(for: fontRequest, cachedProfiles: [])
    check(fontProfile?.resizable == false, "models a proven unresizable application")
    check(fontProfile.map { plannedSize(for: fontRequest, profile: $0) } == CGSize(width: 1000, height: 650),
          "does not reserve below a proven application minimum")
    let unknownRequest = BatchRequestItem(
        app: "example.unknown", width: 500, height: 400,
        launchWidth: nil, launchHeight: nil, minimumWidth: nil, minimumHeight: nil, resizable: nil
    )
    check(resolvedGeometry(for: unknownRequest, cachedProfiles: []) == nil,
          "keeps unknown launch geometry explicit")

    let launchReservation = Reservation(
        id: "launch", app: "example.launch", createdAt: 0, expiresAt: 100,
        protectedDisplayID: 1, targetDisplayID: 2,
        region: Rect(x: 1500, y: 100, width: 500, height: 400),
        baselineWindowIDs: [], appWasRunning: false, batchID: nil
    )
    var launchSnapshot = base
    check(targetWindow(snapshot: launchSnapshot, reservation: launchReservation) == .none,
          "finds no launch window when no post-baseline candidate exists")
    let firstLaunchWindow = WindowInfo(
        id: 40, pid: 40, bundleIdentifier: "example.launch",
        bounds: Rect(x: 1500, y: 100, width: 500, height: 400), layer: 0
    )
    launchSnapshot.windows.append(firstLaunchWindow)
    check(targetWindow(snapshot: launchSnapshot, reservation: launchReservation) == .unique(firstLaunchWindow),
          "binds one unique post-baseline launch window")
    launchSnapshot.windows.append(WindowInfo(
        id: 41, pid: 40, bundleIdentifier: "example.launch",
        bounds: Rect(x: 2100, y: 100, width: 420, height: 320), layer: 0
    ))
    if case .ambiguous(let candidates) = targetWindow(snapshot: launchSnapshot, reservation: launchReservation) {
        check(candidates.map(\.id) == [40, 41], "refuses multiple post-baseline launch windows")
    } else {
        check(false, "refuses multiple post-baseline launch windows")
    }

    let geometryTarget = CGRect(x: 100, y: 200, width: 600, height: 400)
    check(uniqueGeometryMatch(candidates: [geometryTarget], target: geometryTarget) == .unique(0),
          "accepts one exact Accessibility geometry match")
    check(uniqueGeometryMatch(
        candidates: [CGRect(x: 106, y: 194, width: 604, height: 396)],
        target: geometryTarget
    ) == .unique(0), "accepts one bounded Accessibility geometry match")
    check(uniqueGeometryMatch(candidates: [geometryTarget, geometryTarget], target: geometryTarget) == .ambiguous,
          "refuses tied Accessibility geometry matches")
    check(uniqueGeometryMatch(
        candidates: [CGRect(x: 200, y: 300, width: 600, height: 400)],
        target: geometryTarget
    ) == .none, "refuses an out-of-tolerance Accessibility geometry match")

    let ownedWindow = WindowInfo(
        id: 42, pid: 42, bundleIdentifier: "example.launch",
        bounds: Rect(x: 1500, y: 100, width: 500, height: 400), layer: 0
    )
    let owned = try? makeOwnedRestoreRecord(
        reservation: launchReservation,
        window: ownedWindow,
        originalBounds: ownedWindow.bounds.cgRect
    )
    func receiptAuthenticates(_ record: RestoreRecord?, _ receipt: String?) -> Bool {
        guard let record, let receipt else { return false }
        do {
            try authenticate(record, receipt: receipt)
            return true
        } catch {
            return false
        }
    }
    check(receiptAuthenticates(owned?.record, owned?.receipt),
          "accepts the caller-held receipt for the original lifecycle record")
    var tamperedRecord = owned?.record
    tamperedRecord?.windowID = 999
    check(!receiptAuthenticates(tamperedRecord, owned?.receipt),
          "rejects a caller-held receipt after lifecycle identity tampering")
    check(!receiptAuthenticates(owned?.record, "wrong-receipt"),
          "rejects an incorrect caller-held lifecycle receipt")

    func resolvedItem(_ index: Int, _ app: String, _ width: Double, _ height: Double) -> ResolvedBatchItem {
        let request = BatchRequestItem(
            app: app, width: width, height: height,
            launchWidth: width, launchHeight: height,
            minimumWidth: width, minimumHeight: height, resizable: false
        )
        let profile = resolvedGeometry(for: request, cachedProfiles: [])!
        return ResolvedBatchItem(
            requestIndex: index, request: request,
            plannedSize: CGSize(width: width, height: height), profile: profile
        )
    }

    let fittingBatch = [
        resolvedItem(0, "example.one", 500, 400),
        resolvedItem(1, "example.two", 500, 400),
        resolvedItem(2, "example.three", 500, 400)
    ]
    let batchSolution = solveBatchPlacements(items: fittingBatch, snapshot: base, reservations: [])
    check(batchSolution?.count == 3, "preflights a complete fitting application group")
    check(batchSolution.map { placements in
        for firstIndex in placements.indices {
            for secondIndex in placements.indices where secondIndex > firstIndex {
                if placements[firstIndex].region.intersects(placements[secondIndex].region) { return false }
            }
        }
        return true
    } == true, "keeps every batch reservation disjoint")
    let alternateBatchSolution = solveBatchPlacements(
        items: fittingBatch,
        snapshot: base,
        reservations: [],
        layoutVariant: 1
    )
    check(alternateBatchSolution?.count == 3, "finds a complete alternate layout variant")
    check(alternateBatchSolution.map { alternate in
        guard let standard = batchSolution else { return false }
        return zip(standard, alternate).contains { first, second in
            first.display.id != second.display.id || first.region != second.region
        }
    } == true, "chooses different safe regions for an alternate layout variant")

    let noFitBatch = [
        resolvedItem(0, "example.large-one", 1000, 700),
        resolvedItem(1, "example.large-two", 1000, 700)
    ]
    check(solveBatchPlacements(items: noFitBatch, snapshot: base, reservations: []) == nil,
          "refuses a complete group that cannot fit")

    var remainingSnapshot = base
    let alreadyPlaced = WindowInfo(
        id: 30, pid: 30, bundleIdentifier: "example.placed",
        bounds: Rect(x: 1440, y: 24, width: 700, height: 500), layer: 0
    )
    let justLaunched = WindowInfo(
        id: 31, pid: 31, bundleIdentifier: "example.current",
        bounds: Rect(x: 1480, y: 70, width: 650, height: 450), layer: 0
    )
    remainingSnapshot.windows += [alreadyPlaced, justLaunched]
    let remainingSolution = solveBatchPlacements(
        items: [
            resolvedItem(0, "example.current", 650, 450),
            resolvedItem(1, "example.remaining", 500, 400)
        ],
        snapshot: remainingSnapshot,
        reservations: [],
        ignoringWindowIDs: [justLaunched.id]
    )
    check(remainingSolution?.count == 2, "replans the current and remaining applications together")
    check(remainingSolution.map { placements in
        placements.allSatisfy { !$0.region.intersects(alreadyPlaced.bounds.cgRect) }
    } == true, "preserves space already occupied by a placed batch window")

    let proofRegion = Rect(x: 1500, y: 100, width: 500, height: 400)
    let proofItem = BatchPlanItem(
        app: "example.proof", reservationID: "proof-reservation",
        requestedSize: SizeValue(width: 500, height: 400),
        plannedSize: SizeValue(width: 500, height: 400),
        targetDisplayID: 2, region: proofRegion,
        geometrySource: "test", resizable: false,
        status: .placed, actualLaunchBounds: proofRegion,
        windowID: 20, pid: 20, finalBounds: proofRegion
    )
    let proofBatch = BatchPlan(
        id: "proof-batch", createdAt: 0, expiresAt: 100,
        protectedDisplayID: 1, status: .completed,
        launchOrder: ["example.proof"], items: [proofItem], failureReason: nil,
        baselineFrontmostBundleIdentifier: "com.openai.chat",
        baselineDisplays: base.displays, baselineWindows: base.windows
    )
    var proofSnapshot = base
    let proofWindow = WindowInfo(
        id: 20, pid: 20, bundleIdentifier: "example.proof", bounds: proofRegion, layer: 0
    )
    proofSnapshot.windows.append(proofWindow)
    let proofReservation = Reservation(
        id: "proof-reservation", app: "example.proof", createdAt: 0, expiresAt: 100,
        protectedDisplayID: 1, targetDisplayID: 2, region: proofRegion,
        baselineWindowIDs: [], appWasRunning: false, batchID: "proof-batch"
    )
    let proofOwned = try! makeOwnedRestoreRecord(
        reservation: proofReservation,
        window: proofWindow,
        originalBounds: proofRegion.cgRect
    )
    var proofState = PersistentState()
    proofState.restores = [proofOwned.record]
    let proofReceipts = ["proof-reservation": proofOwned.receipt]
    let successfulProof = buildBatchProof(
        batch: proofBatch,
        snapshot: proofSnapshot,
        state: proofState,
        receipts: proofReceipts
    )
    check(successfulProof.complete, "marks a fully placed batch proof complete")
    check(successfulProof.ownershipAuthenticated, "authenticates every completed proof lifecycle")
    check(successfulProof.baselineWindowsEqual, "proves exact baseline-window equality")
    check(successfulProof.pairwiseDisjoint, "proves final windows are pairwise disjoint")
    check(successfulProof.allWindowsInReservations, "proves final windows remain in reservations")
    check(successfulProof.allWindowsOnDisplays, "proves final windows remain on active displays")
    check(successfulProof.frontmostRestored, "proves the baseline frontmost application is restored")
    check(successfulProof.ok, "combines complete geometry and focus proof into one result")
    let unauthenticatedProof = buildBatchProof(
        batch: proofBatch,
        snapshot: proofSnapshot,
        state: proofState
    )
    check(!unauthenticatedProof.ownershipAuthenticated,
          "refuses completed proof without caller-held lifecycle receipts")
    check(!unauthenticatedProof.ok,
          "keeps geometry-only proof from becoming authoritative")
    let successfulSummary = summarizeProof(successfulProof)
    check(successfulSummary.ok, "keeps the combined result in compact proof output")
    check(successfulSummary.changedBaselineWindowIDs.isEmpty,
          "keeps unchanged baseline windows compact")

    proofSnapshot.windows[0].bounds.x += 1
    let changedBaselineProof = buildBatchProof(
        batch: proofBatch,
        snapshot: proofSnapshot,
        state: proofState,
        receipts: proofReceipts
    )
    check(!changedBaselineProof.baselineWindowsEqual, "detects a changed pre-existing window")
    check(!changedBaselineProof.ok, "fails the combined proof when baseline geometry changes")
    check(summarizeProof(changedBaselineProof).changedBaselineWindowIDs == [10],
          "identifies changed baseline windows in compact proof output")

    let safeWindow = WindowSafety(edited: false, modal: false, hasSheet: false, hasCloseButton: true)
    let editedWindow = WindowSafety(edited: true, modal: false, hasSheet: false, hasCloseButton: true)
    let modalWindow = WindowSafety(edited: false, modal: true, hasSheet: false, hasCloseButton: true)
    check(cleanupAction(appWasRunning: false, windowPresent: true, safety: safeWindow, leaveOpen: false) == .closeWindowThenQuit,
          "quits an app launched by the agent")
    check(cleanupAction(appWasRunning: true, windowPresent: true, safety: safeWindow, leaveOpen: false) == .closeCreatedWindow,
          "preserves a pre-existing app process")
    check(cleanupAction(appWasRunning: false, windowPresent: true, safety: editedWindow, leaveOpen: false) == .preserveEdited,
          "preserves edited content")
    check(cleanupAction(appWasRunning: false, windowPresent: true, safety: modalWindow, leaveOpen: false) == .preserveModal,
          "preserves modal state")
    check(cleanupAction(appWasRunning: false, windowPresent: true, safety: safeWindow, leaveOpen: true) == .leaveOpen,
          "honors an explicit leave-open decision")
    check(cleanupAction(appWasRunning: false, windowPresent: false, safety: nil, leaveOpen: false) == .alreadyClosed,
          "finalizes an already-closed window")

    if failures.isEmpty {
        emit(SimpleOutput(ok: true, status: "passed", message: "\(checkCount) placement and cleanup scenarios passed"))
    } else {
        emit(SimpleOutput(ok: false, status: "failed", message: failures.joined(separator: "; ")))
        exit(8)
    }
}

do {
    let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
    let store = StateStore()
    switch arguments.command {
    case "scan":
        emit(try desktopSnapshot())
    case "preflight":
        try preflight(arguments, store: store)
    case "batch-status":
        try batchStatus(arguments, store: store)
    case "prove":
        try prove(arguments, store: store)
    case "prepare":
        try prepare(arguments, store: store)
    case "place":
        try place(arguments, store: store)
    case "verify":
        try verify(arguments, store: store)
    case "restore":
        try restore(arguments, store: store)
    case "finish":
        try finish(arguments, store: store)
    case "finish-batch":
        try finishBatch(arguments, store: store)
    case "release":
        try release(arguments, store: store)
    case "self-test":
        runSelfTests()
    case "help", "--help", "-h":
        print(usageText)
    default:
        throw WorkspaceError.usage("Unknown command: \(arguments.command)\n\n\(usageText)")
    }
} catch {
    emit(SimpleOutput(ok: false, status: "error", message: String(describing: error)))
    exit(2)
}
