import AppKit
import ApplicationServices
import CoreGraphics
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
}

private struct PersistentState: Codable {
    var reservations: [Reservation] = []
    var restores: [RestoreRecord] = []
}

private struct PlacementChoice {
    var display: DisplayInfo
    var region: CGRect
}

private struct PointValue: Codable {
    var x: Double
    var y: Double
}

private struct ComputerUseDrag: Codable {
    var app: String
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
    var dryRun: Bool
    var message: String
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
        guard let value = Double(raw), value > 0 else {
            throw WorkspaceError.usage("\(name) must be a positive number")
        }
        return value
    }
}

private let usageText = """
Usage:
  computer-use-workspace scan
  computer-use-workspace prepare --app BUNDLE_ID [--width 900] [--height 700] [--ttl 90] [--dry-run]
  computer-use-workspace place --reservation ID [--wait 6]
  computer-use-workspace verify --reservation ID
  computer-use-workspace restore --reservation ID
  computer-use-workspace finish --reservation ID [--apply] [--leave-open] [--confirm-closed]
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
        let now = Date().timeIntervalSince1970
        state.reservations.removeAll { $0.expiresAt <= now }
        state.restores.removeAll { now - $0.createdAt > 86_400 }
        let result = try body(&state)
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: .atomic)
        return result
    }

    private func readState() -> PersistentState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistentState.self, from: data) else {
            return PersistentState()
        }
        return state
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
    desiredHeight: Double
) -> PlacementChoice? {
    let protectedID = snapshot.focusedDisplayID
    let otherDisplays = snapshot.displays.filter { $0.id != protectedID }
    let candidates = otherDisplays.isEmpty ? snapshot.displays : otherDisplays
    let minimumWidth = min(480, desiredWidth)
    let minimumHeight = min(320, desiredHeight)
    var choices: [PlacementChoice] = []

    for display in candidates {
        let visible = display.visibleFrame.cgRect
        var freeRects = [visible]
        let windowRects = snapshot.windows.compactMap { window in
            padded(window.bounds.cgRect, by: 12, clippedTo: visible)
        }
        let reservationRects = reservations.compactMap { reservation in
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
        let firstScore = first.region.areaValue
        let secondScore = second.region.areaValue
        if firstScore == secondScore {
            if first.region.minY == second.region.minY { return first.region.minX > second.region.minX }
            return first.region.minY > second.region.minY
        }
        return firstScore < secondScore
    }
}

private func findAXWindow(pid: Int32, matching bounds: CGRect) -> AXUIElement? {
    let application = AXUIElementCreateApplication(pid)
    var rawValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawValue) == .success,
          let windows = rawValue as? [AXUIElement] else {
        return nil
    }
    var best: (element: AXUIElement, distance: Double)?
    for window in windows {
        guard let current = axBounds(window) else { continue }
        let distance = abs(current.minX - bounds.minX) + abs(current.minY - bounds.minY)
            + abs(current.width - bounds.width) + abs(current.height - bounds.height)
        if best == nil || distance < best!.distance {
            best = (window, distance)
        }
    }
    return best?.element
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
        let exists = try desktopSnapshot().windows.contains { $0.id == id && $0.pid == pid }
        if !exists { return true }
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

private func targetWindow(snapshot: DesktopSnapshot, reservation: Reservation) -> WindowInfo? {
    let matching = snapshot.windows.filter { $0.bundleIdentifier == reservation.app }
    let baseline = Set(reservation.baselineWindowIDs)
    let newWindows = matching.filter { !baseline.contains($0.id) }
    if !baseline.isEmpty { return newWindows.max { $0.bounds.area < $1.bounds.area } }
    return newWindows.max { $0.bounds.area < $1.bounds.area } ?? matching.max { $0.bounds.area < $1.bounds.area }
}

private func desiredBounds(for window: WindowInfo, region: Rect) -> CGRect {
    let current = window.bounds.cgRect
    let target = region.cgRect
    let width = min(current.width, target.width)
    let height = min(current.height, target.height)
    return CGRect(x: target.minX, y: target.minY, width: width, height: height)
}

private func dragPlan(app: String, from original: CGRect, to target: CGRect) -> ComputerUseDrag {
    let sourceX = original.midX
    let sourceY = original.minY + min(18, original.height / 4)
    let targetX = target.minX + original.width / 2
    let targetY = target.minY + min(18, original.height / 4)
    return ComputerUseDrag(
        app: app,
        from: PointValue(x: sourceX, y: sourceY),
        to: PointValue(x: targetX, y: targetY)
    )
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
        let snapshot = try desktopSnapshot()
        if let bounds = snapshot.windows.first(where: { $0.id == id && $0.pid == pid })?.bounds {
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
        guard let choice = choosePlacement(
            snapshot: snapshot,
            reservations: state.reservations,
            desiredWidth: width,
            desiredHeight: height
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
                dryRun: dryRun,
                message: "No unoccupied region met the minimum placement size"
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
                appWasRunning: appWasRunning
            ))
        }
        return PrepareOutput(
            ok: true,
            status: dryRun ? "dry_run" : "reserved",
            reservationID: dryRun ? nil : id,
            app: app,
            protectedDisplayID: snapshot.focusedDisplayID,
            targetDisplayID: choice.display.id,
            region: Rect(choice.region),
            expiresAt: dryRun ? nil : expiration,
            appWasRunning: appWasRunning,
            dryRun: dryRun,
            message: dryRun ? "Safe placement found; nothing was reserved or moved" : "Safe placement reserved"
        )
    }
    emit(output)
    if !output.ok { exit(3) }
}

private func place(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let wait = try arguments.double("--wait", default: 6)
    let reservation = try store.withState { state -> Reservation in
        guard let value = state.reservations.first(where: { $0.id == reservationID }) else {
            throw WorkspaceError.runtime("Reservation not found or expired: \(reservationID)")
        }
        return value
    }

    let deadline = Date().addingTimeInterval(wait)
    var snapshot = try desktopSnapshot()
    var window = targetWindow(snapshot: snapshot, reservation: reservation)
    while window == nil, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.15)
        snapshot = try desktopSnapshot()
        window = targetWindow(snapshot: snapshot, reservation: reservation)
    }
    guard let window else {
        emit(ActionOutput(
            ok: false, status: "no_new_window", reservationID: reservationID, app: reservation.app,
            windowID: nil, originalBounds: nil, currentBounds: nil, targetRegion: reservation.region,
            computerUseDrag: nil, message: "No new target-app window appeared before the placement deadline"
        ))
        exit(4)
    }

    let original = window.bounds.cgRect
    let target = desiredBounds(for: window, region: reservation.region)
    let restore = RestoreRecord(
        reservationID: reservationID,
        app: reservation.app,
        pid: window.pid,
        windowID: window.id,
        originalBounds: Rect(original),
        targetRegion: reservation.region,
        createdAt: Date().timeIntervalSince1970,
        appWasRunning: reservation.appWasRunning
    )
    try store.withState { state in
        state.restores.removeAll { $0.reservationID == reservationID }
        state.restores.append(restore)
    }

    if AXIsProcessTrusted(), let axWindow = findAXWindow(pid: window.pid, matching: original) {
        let result = setAXBounds(axWindow, rect: target)
        if result == .success {
            let updated = try waitForSettledWindow(id: window.id, pid: window.pid, target: target)
            let settled = updated.map { bounds in
                reservation.region.cgRect.insetBy(dx: -8, dy: -8).contains(bounds.cgRect)
            } == true
            if settled {
                try store.withState { state in
                    state.reservations.removeAll { $0.id == reservationID }
                }
            }
            emit(ActionOutput(
                ok: settled, status: settled ? "placed" : "placement_unsettled",
                reservationID: reservationID, app: reservation.app,
                windowID: window.id, originalBounds: Rect(original), currentBounds: updated,
                targetRegion: reservation.region, computerUseDrag: nil,
                message: settled
                    ? "Window placed and verified through macOS Accessibility"
                    : "Accessibility accepted the move, but the window server did not settle inside the reservation"
            ))
            if !settled { exit(7) }
            return
        }
    }

    emit(ActionOutput(
        ok: false, status: "computer_use_drag_required", reservationID: reservationID, app: reservation.app,
        windowID: window.id, originalBounds: Rect(original), currentBounds: Rect(original),
        targetRegion: reservation.region, computerUseDrag: dragPlan(app: reservation.app, from: original, to: target),
        message: "Direct Accessibility placement is unavailable; execute the returned drag with Computer Use, then run verify"
    ))
    exit(5)
}

private func verify(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let pair = try store.withState { state -> (Reservation?, RestoreRecord?) in
        (state.reservations.first { $0.id == reservationID }, state.restores.first { $0.reservationID == reservationID })
    }
    guard let record = pair.1 else {
        throw WorkspaceError.runtime("Restore record not found for reservation: \(reservationID)")
    }
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
        try store.withState { state in
            state.reservations.removeAll { $0.id == reservationID }
        }
    }
    emit(ActionOutput(
        ok: isInside, status: isInside ? "verified" : "verification_failed", reservationID: reservationID,
        app: record.app, windowID: record.windowID, originalBounds: record.originalBounds,
        currentBounds: Rect(current), targetRegion: record.targetRegion, computerUseDrag: nil,
        message: isInside ? "Window is inside the reserved region" : "Window is outside the reserved region"
    ))
    if !isInside { exit(7) }
}

private func restore(_ arguments: Arguments, store: StateStore) throws {
    let reservationID = try arguments.required("--reservation")
    let record = try store.withState { state -> RestoreRecord in
        guard let value = state.restores.first(where: { $0.reservationID == reservationID }) else {
            throw WorkspaceError.runtime("Restore record not found: \(reservationID)")
        }
        return value
    }
    let snapshot = try desktopSnapshot()
    guard let window = snapshot.windows.first(where: { $0.id == record.windowID && $0.pid == record.pid }) else {
        throw WorkspaceError.runtime("The original window is no longer available")
    }
    let current = window.bounds.cgRect
    if AXIsProcessTrusted(), let axWindow = findAXWindow(pid: window.pid, matching: current),
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
    let apply = arguments.flags.contains("--apply")
    let leaveOpen = arguments.flags.contains("--leave-open")
    let confirmClosed = arguments.flags.contains("--confirm-closed")
    if confirmClosed && (apply || leaveOpen) {
        throw WorkspaceError.usage("--confirm-closed cannot be combined with --apply or --leave-open")
    }

    let record = try store.withState { state -> RestoreRecord in
        guard let value = state.restores.first(where: { $0.reservationID == reservationID }) else {
            throw WorkspaceError.runtime("Lifecycle record not found: \(reservationID)")
        }
        return value
    }

    func finalize() throws {
        try store.withState { state in
            state.restores.removeAll { $0.reservationID == reservationID }
            state.reservations.removeAll { $0.id == reservationID }
        }
    }

    var snapshot = try desktopSnapshot()
    var window = snapshot.windows.first { $0.id == record.windowID && $0.pid == record.pid }

    if confirmClosed {
        guard window == nil else {
            emit(FinishOutput(
                ok: false,
                status: "cleanup_not_complete",
                reservationID: reservationID,
                app: record.app,
                appWasRunning: record.appWasRunning,
                windowID: record.windowID,
                windowPresent: true,
                safety: nil,
                plannedAction: record.appWasRunning ? .closeCreatedWindow : .closeWindowThenQuit,
                applied: false,
                appTerminated: nil,
                message: "The task-owned window is still open"
            ))
            exit(9)
        }
        var appTerminated: Bool?
        if !record.appWasRunning && snapshot.windows.allSatisfy({ $0.bundleIdentifier != record.app }) {
            appTerminated = gracefullyTerminate(pid: record.pid)
        }
        try finalize()
        emit(FinishOutput(
            ok: true,
            status: "cleanup_verified",
            reservationID: reservationID,
            app: record.app,
            appWasRunning: record.appWasRunning,
            windowID: record.windowID,
            windowPresent: false,
            safety: nil,
            plannedAction: .alreadyClosed,
            applied: true,
            appTerminated: appTerminated,
            message: "Task-owned window closure verified and lifecycle state finalized"
        ))
        return
    }

    let axWindow = window.flatMap { value in
        AXIsProcessTrusted() ? findAXWindow(pid: value.pid, matching: value.bounds.cgRect) : nil
    }
    let safety = axWindow.map(windowSafety)
    let action = cleanupAction(
        appWasRunning: record.appWasRunning,
        windowPresent: window != nil,
        safety: safety,
        leaveOpen: leaveOpen
    )

    if !apply {
        emit(FinishOutput(
            ok: true,
            status: "cleanup_plan",
            reservationID: reservationID,
            app: record.app,
            appWasRunning: record.appWasRunning,
            windowID: record.windowID,
            windowPresent: window != nil,
            safety: safety,
            plannedAction: action,
            applied: false,
            appTerminated: nil,
            message: "Cleanup plan ready; review it and rerun with --apply"
        ))
        return
    }

    switch action {
    case .leaveOpen:
        try finalize()
        emit(FinishOutput(
            ok: true, status: "left_open", reservationID: reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: window != nil, safety: safety, plannedAction: action,
            applied: true, appTerminated: nil,
            message: "Task-owned window intentionally left open and lifecycle state finalized"
        ))
        return

    case .preserveEdited:
        emit(FinishOutput(
            ok: true, status: "preserved_edited", reservationID: reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: true, safety: safety, plannedAction: action,
            applied: false, appTerminated: nil,
            message: "Window reports edited content and was preserved"
        ))
        return

    case .preserveModal:
        emit(FinishOutput(
            ok: true, status: "preserved_modal", reservationID: reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: true, safety: safety, plannedAction: action,
            applied: false, appTerminated: nil,
            message: "Window has a modal surface or sheet and was preserved"
        ))
        return

    case .alreadyClosed:
        var appTerminated: Bool?
        if !record.appWasRunning && snapshot.windows.allSatisfy({ $0.bundleIdentifier != record.app }) {
            appTerminated = gracefullyTerminate(pid: record.pid)
        }
        try finalize()
        emit(FinishOutput(
            ok: true, status: "already_closed", reservationID: reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: false, safety: safety, plannedAction: action,
            applied: true, appTerminated: appTerminated,
            message: "Task-owned window was already closed; lifecycle state finalized"
        ))
        return

    case .closeCreatedWindow, .closeWindowThenQuit:
        guard let axWindow, safety?.hasCloseButton == true else {
            emit(FinishOutput(
                ok: false, status: "computer_use_close_required", reservationID: reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: safety, plannedAction: action,
                applied: false, appTerminated: nil,
                message: "Direct close is unavailable; close the exact task-owned window with Computer Use, then run finish --confirm-closed"
            ))
            exit(5)
        }
        let closeResult = closeAXWindow(axWindow)
        guard closeResult == .success else {
            emit(FinishOutput(
                ok: false, status: "computer_use_close_required", reservationID: reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: safety, plannedAction: action,
                applied: false, appTerminated: nil,
                message: "macOS rejected the direct close; close the exact task-owned window with Computer Use, then run finish --confirm-closed"
            ))
            exit(5)
        }
        guard try waitForWindowToClose(id: record.windowID, pid: record.pid) else {
            emit(FinishOutput(
                ok: false, status: "cleanup_pending", reservationID: reservationID,
                app: record.app, appWasRunning: record.appWasRunning, windowID: record.windowID,
                windowPresent: true, safety: safety, plannedAction: action,
                applied: false, appTerminated: nil,
                message: "Close was requested, but the window remains open; preserve it for user review"
            ))
            exit(9)
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
                message += appTerminated == true
                    ? "; agent-launched app quit"
                    : "; app has no visible windows but did not quit"
            }
        }
        try finalize()
        emit(FinishOutput(
            ok: true, status: "cleaned_up", reservationID: reservationID, app: record.app,
            appWasRunning: record.appWasRunning, windowID: record.windowID,
            windowPresent: window != nil, safety: safety, plannedAction: action,
            applied: true, appTerminated: appTerminated, message: message
        ))
    }
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
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
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

    let full = DesktopSnapshot(
        capturedAt: 0,
        accessibilityTrusted: true,
        frontmostBundleIdentifier: "com.openai.chat",
        focusedDisplayID: 1,
        pointerDisplayID: 1,
        displays: [left, right],
        windows: [WindowInfo(id: 12, pid: 12, bundleIdentifier: "example.full", bounds: right.visibleFrame, layer: 0)]
    )
    check(choosePlacement(snapshot: full, reservations: [], desiredWidth: 900, desiredHeight: 700) == nil,
          "returns no safe placement instead of covering the focused display")

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
        emit(SimpleOutput(ok: true, status: "passed", message: "10 placement and cleanup scenarios passed"))
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
