import Cocoa

class InstallerWindowController: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "安装助手")
    private let statusLabel = NSTextField(labelWithString: "将 .dmg / .app / .pkg 拖到图标上即可自动审核安装")
    private let progress = NSProgressIndicator()
    private let actionButton = NSButton(title: "选择文件", target: nil, action: nil)
    private let friendButton = NSButton(title: "发送朋友审批", target: nil, action: nil)

    private var currentPath: String?
    private var runningProcess: Process?
    private var inputPipe: Pipe?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 176),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.center()
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let bg = NSVisualEffectView(frame: contentView.bounds)
        bg.autoresizingMask = [.width, .height]
        bg.material = .hudWindow
        bg.state = .active
        contentView.addSubview(bg)

        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 24, y: 120, width: 332, height: 24)
        bg.addSubview(titleLabel)

        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2
        statusLabel.frame = NSRect(x: 24, y: 74, width: 332, height: 38)
        bg.addSubview(statusLabel)

        progress.style = .bar
        progress.isIndeterminate = true
        progress.isHidden = true
        progress.frame = NSRect(x: 32, y: 52, width: 316, height: 16)
        bg.addSubview(progress)

        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(pickFile)
        actionButton.frame = NSRect(x: 130, y: 16, width: 120, height: 28)
        bg.addSubview(actionButton)

        friendButton.bezelStyle = .rounded
        friendButton.target = self
        friendButton.action = #selector(approveViaFriend)
        friendButton.isHidden = true
        friendButton.frame = NSRect(x: 115, y: 16, width: 150, height: 28)
        bg.addSubview(friendButton)
    }

    @objc private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["dmg", "app", "pkg"]
        if panel.runModal() == .OK, let url = panel.url {
            startInstall(path: url.path)
        }
    }

    func startInstall(path: String) {
        currentPath = path
        let name = URL(fileURLWithPath: path).lastPathComponent
        titleLabel.stringValue = name
        statusLabel.stringValue = "正在检查并审核…"
        progress.isHidden = false
        progress.startAnimation(nil)
        actionButton.isHidden = true
        friendButton.isHidden = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/local/bin/safe-install")
        proc.arguments = [path]

        let outPipe = Pipe()
        let inPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe
        proc.standardInput = inPipe
        self.runningProcess = proc
        self.inputPipe = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.handleOutput(text)
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                outPipe.fileHandleForReading.readabilityHandler = nil
                self.progress.stopAnimation(nil)
                self.progress.isHidden = true
                if p.terminationStatus == 0 {
                    self.statusLabel.stringValue = "✅ 安装完成"
                    self.actionButton.title = "完成"
                    self.actionButton.action = #selector(self.closeApp)
                    self.actionButton.isHidden = false
                    self.friendButton.isHidden = true
                } else {
                    if self.friendButton.isHidden {
                        self.actionButton.title = "关闭"
                        self.actionButton.action = #selector(self.closeApp)
                        self.actionButton.isHidden = false
                    }
                }
            }
        }

        do {
            try proc.run()
        } catch {
            progress.stopAnimation(nil)
            progress.isHidden = true
            statusLabel.stringValue = "请先由管理员完成 safe-install 初始化"
            actionButton.isHidden = false
        }
    }

    private func handleOutput(_ text: String) {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.contains("白名单") || line.contains("AI 审核通过") {
                statusLabel.stringValue = "审核通过，正在安装…"
            } else if line.contains("朋友已在手机上点击同意") {
                statusLabel.stringValue = "朋友已同意，正在安装…"
                friendButton.isHidden = true
            } else if line.contains("是否推送给朋友手机") {
                progress.stopAnimation(nil)
                progress.isHidden = true
                statusLabel.stringValue = "未在自动放行范围内，可发给朋友一键审批"
                friendButton.isHidden = false
            } else if line.contains("等待朋友在手机上点击") {
                friendButton.isHidden = true
                progress.isHidden = false
                progress.startAnimation(nil)
                statusLabel.stringValue = "已推送给朋友，等待点击同意…"
            } else if line.contains("❌") || line.contains("🚫") {
                statusLabel.stringValue = line.replacingOccurrences(of: "❌ [拦截/失败] ", with: "")
            }
        }
    }

    @objc private func approveViaFriend() {
        friendButton.isHidden = true
        progress.isHidden = false
        progress.startAnimation(nil)
        statusLabel.stringValue = "正在推送给朋友…"
        if let data = "y\n正常学习/办公软件\n".data(using: .utf8) {
            inputPipe?.fileHandleForWriting.write(data)
        }
    }

    @objc private func closeApp() {
        NSApp.terminate(nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: InstallerWindowController?
    private var launchedWithFile = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if controller == nil {
            controller = InstallerWindowController()
        }
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        launchedWithFile = true
        if controller == nil {
            controller = InstallerWindowController()
        }
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let first = filenames.first {
            controller?.startInstall(path: first)
        }
        sender.reply(toOpenOrPrint: .success)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
