import Cocoa
import AVFoundation

// MARK: - Impact Detector (Smart Transient Detection)

class ImpactDetector {
    private var audioEngine: AVAudioEngine?
    private var lastTriggerTime: Date = .distantPast

    // Rolling energy history for attack detection
    private var energyHistory: [Float] = []
    private let historySize = 25 // ~0.5s at 50 updates/sec

    // Settings
    var cooldown: TimeInterval = 2.0
    var sensitivity: Float = 6.0   // Attack ratio threshold (higher = less sensitive)
    var minPeak: Float = 0.08      // Minimum absolute peak to even consider
    var isActive = true

    var onImpactDetected: (() -> Void)?

    func start() -> Bool {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else { return false }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, self.isActive else { return }
            self.processAudio(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            return true
        } catch {
            print("Audio engine error: \(error)")
            return false
        }
    }

    private func processAudio(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Calculate peak amplitude
        var peak: Float = 0
        for i in 0..<frameLength {
            let absVal = abs(channelData[i])
            if absVal > peak { peak = absVal }
        }

        // Add to rolling history
        energyHistory.append(peak)
        if energyHistory.count > historySize {
            energyHistory.removeFirst()
        }

        // Need enough history to compare
        guard energyHistory.count >= 10 else { return }

        // Calculate average of history (excluding the last 2 samples — the potential impact)
        let historySlice = energyHistory.prefix(energyHistory.count - 2)
        let avgEnergy = historySlice.reduce(0, +) / Float(historySlice.count)

        // Attack ratio: how much does current peak exceed the recent average?
        let safeAvg = max(avgEnergy, 0.001) // avoid division by zero
        let attackRatio = peak / safeAvg

        // SMART TRIGGER:
        // 1. Attack ratio must be high (sudden spike vs background) — this filters speech/music
        // 2. Peak must be above absolute minimum — this filters quiet noises
        // 3. Cooldown — don't spam
        if attackRatio > sensitivity && peak > minPeak {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let now = Date()
                if now.timeIntervalSince(self.lastTriggerTime) > self.cooldown {
                    self.lastTriggerTime = now
                    self.onImpactDetected?()
                }
            }
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }
}

// MARK: - Audio Player

class SwearPlayer {
    private var audioFiles: [URL] = []
    private var player: Process?

    func loadAudioFiles(from directory: String) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return }
        audioFiles = files
            .filter { $0.hasSuffix(".mp3") }
            .sorted()
            .map { URL(fileURLWithPath: directory).appendingPathComponent($0) }
        print("Loaded \(audioFiles.count) audio files")
    }

    func playRandom() {
        guard !audioFiles.isEmpty else { return }
        let file = audioFiles.randomElement()!

        // Kill previous playback
        player?.terminate()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        proc.arguments = [file.path]
        try? proc.run()
        player = proc
    }

    func stop() {
        player?.terminate()
    }
}

// MARK: - Settings Window

class SettingsWindowController: NSObject {
    var window: NSWindow!
    var detector: ImpactDetector
    var onSettingsChanged: (() -> Void)?

    private var sensitivitySlider: NSSlider!
    private var sensitivityLabel: NSTextField!
    private var cooldownSlider: NSSlider!
    private var cooldownLabel: NSTextField!
    private var minPeakSlider: NSSlider!
    private var minPeakLabel: NSTextField!
    private var statusLabel: NSTextField!

    init(detector: ImpactDetector) {
        self.detector = detector
        super.init()
        setupWindow()
    }

    private func setupWindow() {
        let w: CGFloat = 400
        let h: CGFloat = 340

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "KickMyMac Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        window.contentView = content

        var y = h - 50

        // Title
        let title = makeLabel("KickMyMac", bold: true, size: 18)
        title.frame = NSRect(x: 20, y: y, width: w - 40, height: 30)
        content.addSubview(title)

        y -= 15
        let subtitle = makeLabel("Hit detection settings", bold: false, size: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 20, y: y, width: w - 40, height: 20)
        content.addSubview(subtitle)

        y -= 45

        // Sensitivity (attack ratio threshold)
        let sensTitle = makeLabel("Sensitivity:", bold: true, size: 13)
        sensTitle.frame = NSRect(x: 20, y: y, width: 120, height: 20)
        content.addSubview(sensTitle)

        sensitivityLabel = makeLabel(sensitivityText(), bold: false, size: 12)
        sensitivityLabel.frame = NSRect(x: w - 150, y: y, width: 130, height: 20)
        sensitivityLabel.alignment = .right
        content.addSubview(sensitivityLabel)

        y -= 25
        sensitivitySlider = NSSlider(value: Double(detector.sensitivity),
                                      minValue: 2.0, maxValue: 15.0,
                                      target: self, action: #selector(sensitivityChanged(_:)))
        sensitivitySlider.frame = NSRect(x: 20, y: y, width: w - 40, height: 25)
        sensitivitySlider.numberOfTickMarks = 0
        content.addSubview(sensitivitySlider)

        y -= 15
        let sensHint = makeLabel("Left = more sensitive (reacts to light taps)  |  Right = less sensitive (only hard hits)", bold: false, size: 10)
        sensHint.textColor = .tertiaryLabelColor
        sensHint.frame = NSRect(x: 20, y: y, width: w - 40, height: 15)
        content.addSubview(sensHint)

        y -= 40

        // Cooldown
        let cdTitle = makeLabel("Cooldown:", bold: true, size: 13)
        cdTitle.frame = NSRect(x: 20, y: y, width: 120, height: 20)
        content.addSubview(cdTitle)

        cooldownLabel = makeLabel(cooldownText(), bold: false, size: 12)
        cooldownLabel.frame = NSRect(x: w - 150, y: y, width: 130, height: 20)
        cooldownLabel.alignment = .right
        content.addSubview(cooldownLabel)

        y -= 25
        cooldownSlider = NSSlider(value: detector.cooldown,
                                   minValue: 0.5, maxValue: 5.0,
                                   target: self, action: #selector(cooldownChanged(_:)))
        cooldownSlider.frame = NSRect(x: 20, y: y, width: w - 40, height: 25)
        content.addSubview(cooldownSlider)

        y -= 15
        let cdHint = makeLabel("Minimum time between reactions", bold: false, size: 10)
        cdHint.textColor = .tertiaryLabelColor
        cdHint.frame = NSRect(x: 20, y: y, width: w - 40, height: 15)
        content.addSubview(cdHint)

        y -= 40

        // Min Peak
        let mpTitle = makeLabel("Min. hit strength:", bold: true, size: 13)
        mpTitle.frame = NSRect(x: 20, y: y, width: 150, height: 20)
        content.addSubview(mpTitle)

        minPeakLabel = makeLabel(minPeakText(), bold: false, size: 12)
        minPeakLabel.frame = NSRect(x: w - 150, y: y, width: 130, height: 20)
        minPeakLabel.alignment = .right
        content.addSubview(minPeakLabel)

        y -= 25
        minPeakSlider = NSSlider(value: Double(detector.minPeak),
                                  minValue: 0.02, maxValue: 0.4,
                                  target: self, action: #selector(minPeakChanged(_:)))
        minPeakSlider.frame = NSRect(x: 20, y: y, width: w - 40, height: 25)
        content.addSubview(minPeakSlider)

        y -= 15
        let mpHint = makeLabel("Ignores sounds quieter than this threshold", bold: false, size: 10)
        mpHint.textColor = .tertiaryLabelColor
        mpHint.frame = NSRect(x: 20, y: y, width: w - 40, height: 15)
        content.addSubview(mpHint)

        y -= 35

        // Test button
        let testButton = NSButton(title: "Test Swear", target: self, action: #selector(testSwear))
        testButton.bezelStyle = .rounded
        testButton.frame = NSRect(x: 20, y: y, width: 120, height: 30)
        content.addSubview(testButton)

        // Status label
        statusLabel = makeLabel("", bold: false, size: 11)
        statusLabel.textColor = .systemGreen
        statusLabel.frame = NSRect(x: 150, y: y + 5, width: w - 170, height: 20)
        content.addSubview(statusLabel)
    }

    private func makeLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        return label
    }

    private func sensitivityText() -> String {
        let val = detector.sensitivity
        if val < 4 { return "Very High (\(String(format: "%.1f", val)))" }
        if val < 7 { return "Medium (\(String(format: "%.1f", val)))" }
        if val < 10 { return "Low (\(String(format: "%.1f", val)))" }
        return "Very Low (\(String(format: "%.1f", val)))"
    }

    private func cooldownText() -> String {
        return "\(String(format: "%.1f", detector.cooldown))s"
    }

    private func minPeakText() -> String {
        let val = detector.minPeak
        if val < 0.05 { return "Very Quiet (\(String(format: "%.2f", val)))" }
        if val < 0.12 { return "Normal (\(String(format: "%.2f", val)))" }
        if val < 0.25 { return "Loud (\(String(format: "%.2f", val)))" }
        return "Very Loud (\(String(format: "%.2f", val)))"
    }

    @objc func sensitivityChanged(_ sender: NSSlider) {
        detector.sensitivity = Float(sender.doubleValue)
        sensitivityLabel.stringValue = sensitivityText()
    }

    @objc func cooldownChanged(_ sender: NSSlider) {
        detector.cooldown = sender.doubleValue
        cooldownLabel.stringValue = cooldownText()
    }

    @objc func minPeakChanged(_ sender: NSSlider) {
        detector.minPeak = Float(sender.doubleValue)
        minPeakLabel.stringValue = minPeakText()
    }

    @objc func testSwear() {
        statusLabel.stringValue = "Playing..."
        onSettingsChanged?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusLabel.stringValue = ""
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let detector = ImpactDetector()
    let player = SwearPlayer()
    var settingsController: SettingsWindowController!
    var activeMenuItem: NSMenuItem!
    var hitCountMenuItem: NSMenuItem!
    var hitCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load audio files
        let audioDir = findAudioDirectory()
        player.loadAudioFiles(from: audioDir)

        // Setup settings window
        settingsController = SettingsWindowController(detector: detector)
        settingsController.onSettingsChanged = { [weak self] in
            self?.onKick()
        }

        // Setup menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "👊 KickMyMac"

        buildMenu()
        requestMicAndStart()
    }

    func findAudioDirectory() -> String {
        // Check inside app bundle first
        let bundlePath = Bundle.main.resourcePath ?? ""
        let bundleAudio = bundlePath + "/audio"
        if FileManager.default.fileExists(atPath: bundleAudio) {
            return bundleAudio
        }

        // Fallback to audio directory next to the app
        let execPath = ProcessInfo.processInfo.arguments[0]
        let appDir = URL(fileURLWithPath: execPath)
            .deletingLastPathComponent() // MacOS/
            .deletingLastPathComponent() // Contents/
            .deletingLastPathComponent() // .app/
            .path
        let adjacentAudio = appDir + "/audio"
        if FileManager.default.fileExists(atPath: adjacentAudio) {
            return adjacentAudio
        }

        // Last fallback: same directory as executable source
        return (URL(fileURLWithPath: execPath).deletingLastPathComponent().path) + "/audio"
    }

    func buildMenu() {
        let menu = NSMenu()

        activeMenuItem = NSMenuItem(title: "Active", action: nil, keyEquivalent: "")
        activeMenuItem.isEnabled = false
        let dot = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        dot?.isTemplate = true
        activeMenuItem.image = dot
        menu.addItem(activeMenuItem)

        hitCountMenuItem = NSMenuItem(title: "Hits: 0", action: nil, keyEquivalent: "")
        hitCountMenuItem.isEnabled = false
        menu.addItem(hitCountMenuItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Pause", action: #selector(toggleActive), keyEquivalent: "p")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let testItem = NSMenuItem(title: "Test", action: #selector(testSwear), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func requestMicAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startDetection()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startDetection()
                    } else {
                        self?.showError("Microphone access denied.\nGrant access in System Settings > Privacy > Microphone.")
                    }
                }
            }
        default:
            showError("Microphone access denied.\nGrant access in System Settings > Privacy > Microphone.")
        }
    }

    func showError(_ msg: String) {
        activeMenuItem.title = "Error"
        statusItem.button?.title = "❌ Error"
        let alert = NSAlert()
        alert.messageText = "KickMyMac"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.runModal()
    }

    func startDetection() {
        detector.onImpactDetected = { [weak self] in
            self?.onKick()
        }

        if !detector.start() {
            showError("Failed to start audio engine.")
        }
    }

    func onKick() {
        hitCount += 1
        hitCountMenuItem.title = "Hits: \(hitCount)"

        player.playRandom()

        // Flash icon
        statusItem.button?.title = "💥 HIT!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            self.statusItem.button?.title = self.detector.isActive ? "👊 KickMyMac" : "😴 Paused"
        }
    }

    @objc func toggleActive() {
        detector.isActive.toggle()
        if detector.isActive {
            activeMenuItem.title = "Active"
            statusItem.button?.title = "👊 KickMyMac"
            // Update menu item
            if let item = statusItem.menu?.item(withTitle: "Resume") {
                item.title = "Pause"
            }
        } else {
            activeMenuItem.title = "Paused"
            statusItem.button?.title = "😴 Paused"
            if let item = statusItem.menu?.item(withTitle: "Pause") {
                item.title = "Resume"
            }
        }
    }

    @objc func openSettings() {
        settingsController.show()
    }

    @objc func testSwear() {
        onKick()
    }

    @objc func quit() {
        detector.stop()
        player.stop()
        NSApp.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
