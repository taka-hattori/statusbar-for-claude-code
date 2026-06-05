import Cocoa

// ── Claude Status Bar ──
// ~/.claude/sessions/*.json (kind=="bg") を読み、status 別件数から
// メニューバーに Claude ロゴを状態色で tint して表示する常駐アプリ。
//   waiting>=1            -> orange  "waiting"
//   waiting==0 & busy>=1  -> green   "busy"
//   busy==0  & idle>=1    -> yellow  "idle"
//   bgセッションなし        -> gray    (薄表示)

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
    var label: String {
        switch self {
        case .waiting: return "waiting"
        case .busy:    return "busy"
        case .idle:    return "idle"
        case .none:    return "idle"
        }
    }
}

func sessionsDir() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".claude/sessions", isDirectory: true)
}

// pid が生存しているか (stale ファイル除外用)。kill(pid,0): 0=alive, EPERM=alive(別ユーザ), ESRCH=dead
func pidAlive(_ pid: Int) -> Bool {
    if pid <= 0 { return false }
    let r = kill(pid_t(pid), 0)
    if r == 0 { return true }
    return errno == EPERM
}

func readCounts() -> Counts {
    var c = Counts()
    let dir = sessionsDir()
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil) else { return c }
    for f in files where f.pathExtension == "json" {
        guard let data = try? Data(contentsOf: f),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        guard (obj["kind"] as? String) == "bg" else { continue }
        // pid 生存チェック (フィールドがあれば)。無ければそのまま採用
        if let pid = obj["pid"] as? Int, !pidAlive(pid) { continue }
        let status = (obj["status"] as? String) ?? ""
        switch status {
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

// 状態色で塗るドット絵 (`#`=塗り / `.`=透過)。
// デフォルトは Claude Code 起動キャラ風。ユーザーは下記いずれかで自由に差し替え可能:
//   1) 環境変数 CLAUDE_STATUSBAR_CHAR にファイルパス
//   2) ~/.config/claude-statusbar/char.txt
// ファイルは `#` と `.` だけの行を並べたテキスト (全行同じ長さ)。
// 静止 (none=グレー時の素体)
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
// busy: 左右の手を交互に上下 + 足を左右にずらす 2フレーム
let FRAME_BUSY_A: [String] = [
    "..############..",
    "..############..",
    "..##.######.##..",
    "####.######.##..",   // 左手↑
    "##############..",
    "################",
    "..##############",   // 右手↓
    "..##############",
    "..############..",
    "...#.#....#.#...",
    "...#.#....#.#...",
]
let FRAME_BUSY_B: [String] = [
    "..############..",
    "..############..",
    "..##.######.##..",
    "..##.######.####",   // 右手↑
    "..##############",
    "################",
    "##############..",   // 左手↓
    "##############..",
    "..############..",
    "....#.#..#.#....",   // 足を内へ
    "....#.#..#.#....",
]
// idle: 目を横一文字(寝てる)にして、頭の右上に zzz を浮かべた静止 (20x16)
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
// waiting: 体の右上に「!」を体の縦半分くらいで出し、上下に跳ねる 2フレーム (20x11)
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

// カスタム char.txt があれば全状態でそれ(静止)を使う
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

// 状態ごとのフレーム列 (複数あればアニメ)
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
    // 高解像度(cell=4px)でクリスプに描き、表示サイズ(points)を小さく設定して縮小表示する
    let cell: CGFloat = 4
    let pw = Int(cell) * cols
    let ph = Int(cell) * rows
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = false
    state.color.setFill()
    for (r, line) in frame.enumerated() {
        for (cI, ch) in line.enumerated() where ch == "#" {
            let x = CGFloat(cI) * cell
            let y = CGFloat(rows - 1 - r) * cell   // 行0=上端なのでy反転
            NSBezierPath(rect: NSRect(x: x, y: y, width: cell, height: cell)).fill()
        }
    }
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    // 表示サイズ(points): 指定 height に合わせ、アスペクト比を維持
    let w = height * CGFloat(cols) / CGFloat(rows)
    let img = NSImage(size: NSSize(width: w, height: height))
    img.addRepresentation(rep)
    img.isTemplate = false
    return img
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var dataTimer: Timer?     // 2.5秒ごとに状態を取得
    var animTimer: Timer?     // busy/waiting のときアイコンをパラパラ動かす
    var frameIndex = 0
    var state: State = .none
    let cellPt: CGFloat = 13.0 / 11.0   // 1セルの表示サイズ(素体11行で約13pt)。装飾付きでも素体サイズ一定
    lazy var menu = NSMenu()
    let infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "今すぐ更新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        refresh()
        dataTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // アニメ用タイマー (busy のときだけフレームを進める)
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { [weak self] _ in
            self?.tickAnimation()
        }
    }

    // データ取得 → 状態確定 → 即描画
    @objc func refresh() {
        let c = readCounts()
        state = stateFor(c)
        if framesFor(state).count <= 1 { frameIndex = 0 }   // 静止状態はフレーム0へ
        draw()
        if let button = statusItem.button {
            button.toolTip = "waiting:\(c.waiting)  busy:\(c.busy)  idle:\(c.idle)" +
                (c.other > 0 ? "  other:\(c.other)" : "")
        }
        infoItem.title = "waiting \(c.waiting) · busy \(c.busy) · idle \(c.idle)" +
            (c.other > 0 ? " · other \(c.other)" : "")
    }

    // 複数フレームある状態(busy/waiting)だけコマ送り
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
        let height = CGFloat(frame.count) * cellPt   // 行数×セルサイズ=装飾分だけ縦に伸びる
        button.image = pixelCharIcon(frame: frame, state: state, height: height)
        button.imagePosition = .imageOnly
        button.title = ""
    }

    @objc func quit() { NSApplication.shared.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Dock に出さない
let delegate = AppDelegate()
app.delegate = delegate
app.run()
