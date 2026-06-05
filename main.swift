import Cocoa

// Claude Status Bar: reads ~/.claude/sessions/*.json (kind == "bg") and shows
// the aggregate session state as an animated menu bar icon.
// Priority: waiting > busy > idle > none.

struct Counts {
    var waiting = 0
    var busy = 0
    var idle = 0
    var other = 0
    var total: Int { waiting + busy + idle + other }
}

enum State {
    case waiting, busy, idle, none

    var color: NSColor {
        switch self {
        case .waiting: return NSColor.systemOrange
        case .busy:    return NSColor.systemGreen
        case .idle:    return NSColor.systemYellow
        case .none:    return NSColor.tertiaryLabelColor
        }
    }
}

func sessionsDir() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions", isDirectory: true)
}

// kill(pid, 0): 0 or EPERM means alive, ESRCH means dead.
func pidAlive(_ pid: Int) -> Bool {
    if pid <= 0 { return false }
    if kill(pid_t(pid), 0) == 0 { return true }
    return errno == EPERM
}

func readCounts() -> Counts {
    var c = Counts()
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: sessionsDir(), includingPropertiesForKeys: nil) else { return c }
    for f in files where f.pathExtension == "json" {
        guard let data = try? Data(contentsOf: f),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        guard (obj["kind"] as? String) == "bg" else { continue }
        if let pid = obj["pid"] as? Int, !pidAlive(pid) { continue }
        switch (obj["status"] as? String) ?? "" {
        case "waiting": c.waiting += 1
        case "busy":    c.busy += 1
        case "idle":    c.idle += 1
        default:        c.other += 1
        }
    }
    return c
}

func stateFor(_ c: Counts) -> State {
    if c.waiting > 0 { return .waiting }
    if c.busy > 0 { return .busy }
    if c.idle > 0 { return .idle }
    return .none
}

// Dot-matrix sprites ('#' filled, '.' transparent), filled with the state color.
// Override via CLAUDE_STATUSBAR_CHAR or ~/.config/claude-statusbar/char.txt.

let FRAME_REST: [String] = [
    "..############..",
    "..############..",
    "..##.######.##..",
    "..##.######.##..",
    "################",
    "################",
    "################",
    "..############..",
    "..############..",
    "...#.#....#.#...",
    "...#.#....#.#...",
]

// busy: hands wave alternately, feet shuffle (2 frames)
let FRAME_BUSY_A: [String] = [
    "..############..",
    "..############..",
    "..##.######.##..",
    "####.######.##..",
    "##############..",
    "################",
    "..##############",
    "..##############",
    "..############..",
    "...#.#....#.#...",
    "...#.#....#.#...",
]
let FRAME_BUSY_B: [String] = [
    "..############..",
    "..############..",
    "..##.######.##..",
    "..##.######.####",
    "..##############",
    "################",
    "##############..",
    "##############..",
    "..############..",
    "....#.#..#.#....",
    "....#.#..#.#....",
]

// idle: horizontal sleepy eyes + floating zzz
let FRAME_IDLE: [String] = [
    "..............###.#.",
    "...............#....",
    "..........###.###...",
    "...........#........",
    "..........###.......",
    "..############......",
    "..############......",
    "..############......",
    "..##..####..##......",
    "################....",
    "################....",
    "################....",
    "..############......",
    "..############......",
    "...#.#....#.#.......",
    "...#.#....#.#.......",
]

// waiting: bouncing "!" at the top-right (2 frames)
let FRAME_WAIT_A: [String] = [
    "..############...##.",
    "..############...##.",
    "..##.######.##...##.",
    "..##.######.##...##.",
    "################....",
    "################.##.",
    "################....",
    "..############......",
    "..############......",
    "...#.#....#.#.......",
    "...#.#....#.#.......",
]
let FRAME_WAIT_B: [String] = [
    "..############......",
    "..############...##.",
    "..##.######.##...##.",
    "..##.######.##...##.",
    "################.##.",
    "################....",
    "################.##.",
    "..############......",
    "..############......",
    "...#.#....#.#.......",
    "...#.#....#.#.......",
]

func loadCustomFrame() -> [String]? {
    var path: String? = ProcessInfo.processInfo.environment["CLAUDE_STATUSBAR_CHAR"]
    if path == nil {
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-statusbar/char.txt").path
        if FileManager.default.fileExists(atPath: p) { path = p }
    }
    if let p = path, let text = try? String(contentsOfFile: p, encoding: .utf8) {
        let rows = text.split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.isEmpty && $0.allSatisfy { $0 == "#" || $0 == "." } }
        if rows.count >= 2, let w = rows.first?.count, rows.allSatisfy({ $0.count == w }) {
            return rows
        }
    }
    return nil
}

let CUSTOM_FRAME: [String]? = loadCustomFrame()

func framesFor(_ state: State) -> [[String]] {
    if let custom = CUSTOM_FRAME { return [custom] }
    switch state {
    case .busy:    return [FRAME_BUSY_A, FRAME_BUSY_B]
    case .waiting: return [FRAME_WAIT_A, FRAME_WAIT_B]
    case .idle:    return [FRAME_IDLE]
    case .none:    return [FRAME_REST]
    }
}

func pixelCharIcon(frame: [String], state: State, height: CGFloat) -> NSImage {
    let rows = frame.count
    let cols = frame[0].count
    let cell: CGFloat = 4   // render crisp at 4px/cell, then downscale to `height`
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(cell) * cols, pixelsHigh: Int(cell) * rows,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current?.shouldAntialias = false
    state.color.setFill()
    for (r, line) in frame.enumerated() {
        for (cI, ch) in line.enumerated() where ch == "#" {
            let y = CGFloat(rows - 1 - r) * cell   // flip Y: matrix row 0 is the top
            NSBezierPath(rect: NSRect(x: CGFloat(cI) * cell, y: y, width: cell, height: cell)).fill()
        }
    }
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: NSSize(width: height * CGFloat(cols) / CGFloat(rows), height: height))
    img.addRepresentation(rep)
    img.isTemplate = false
    return img
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var dataTimer: Timer?
    var animTimer: Timer?
    var frameIndex = 0
    var state: State = .none
    let cellPt: CGFloat = 13.0 / 11.0   // display size per cell; keeps the body ~constant
    lazy var menu = NSMenu()
    let infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh now", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        refresh()
        dataTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { [weak self] _ in
            self?.tickAnimation()
        }
    }

    @objc func refresh() {
        let c = readCounts()
        state = stateFor(c)
        if framesFor(state).count <= 1 { frameIndex = 0 }
        draw()
        statusItem.button?.toolTip = "waiting:\(c.waiting)  busy:\(c.busy)  idle:\(c.idle)" +
            (c.other > 0 ? "  other:\(c.other)" : "")
        infoItem.title = "waiting \(c.waiting) · busy \(c.busy) · idle \(c.idle)" +
            (c.other > 0 ? " · other \(c.other)" : "")
    }

    func tickAnimation() {
        let n = framesFor(state).count
        guard n > 1 else { return }
        frameIndex = (frameIndex + 1) % n
        draw()
    }

    func draw() {
        guard let button = statusItem.button else { return }
        let frames = framesFor(state)
        let frame = frames[min(frameIndex, frames.count - 1)]
        button.image = pixelCharIcon(frame: frame, state: state, height: CGFloat(frame.count) * cellPt)
        button.imagePosition = .imageOnly
        button.title = ""
    }

    @objc func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
