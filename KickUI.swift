import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hitCountItem: NSMenuItem!
    var hitCount = 0
    var audioFiles: [String] = []
    var audioProcess: Process?
    var lastPlayed: String = ""
    var shuffled: [String] = []
    var shuffleIndex = 0
    let socketPath = "/tmp/kickmymac.sock.ui"

    func applicationDidFinishLaunching(_ n: Notification) {
        loadAudio()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "👊"
        statusItem.button?.font = NSFont.systemFont(ofSize: 14)

        let menu = NSMenu()
        hitCountItem = menu.addItem(withTitle: "Hits: 0", action: nil, keyEquivalent: "")
        hitCountItem.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Test", action: #selector(testHit), keyEquivalent: "t").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q").target = self
        statusItem.menu = menu

        // Listen for hits in background
        DispatchQueue.global().async { self.listenForHits() }
    }

    func loadAudio() {
        let dir = findAudioDir()
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        audioFiles = files.filter { $0.lowercased().hasSuffix(".mp3") }.map { "\(dir)/\($0)" }
        print("Loaded \(audioFiles.count) audio files from \(dir)")
    }

    func findAudioDir() -> String {
        let base = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
        // Check next to binary
        let d1 = "\(base)/audio"
        if FileManager.default.fileExists(atPath: d1) { return d1 }
        // Check in home dir
        let d2 = NSHomeDirectory() + "/Documents/KickMyMac/audio"
        if FileManager.default.fileExists(atPath: d2) { return d2 }
        return d1
    }

    func listenForHits() {
        // Remove old socket
        unlink(socketPath)

        let fd = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { print("socket() failed"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { src in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), src)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sptr in
                Darwin.bind(fd, sptr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else { print("bind() failed: \(errno)"); return }
        chmod(socketPath, 0o777)
        print("Listening on \(socketPath)")

        var buf = [UInt8](repeating: 0, count: 256)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                let msg = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
                if msg.hasPrefix("HIT") {
                    DispatchQueue.main.async { self.onHit() }
                }
            }
        }
    }

    func onHit() {
        hitCount += 1
        hitCountItem.title = "Hits: \(hitCount)"
        playRandom()
        statusItem.button?.title = "💥"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.statusItem.button?.title = "👊"
        }
    }

    func playRandom() {
        guard !audioFiles.isEmpty else { return }
        audioProcess?.terminate()

        // Shuffle deck approach: play all files before repeating any
        if shuffleIndex >= shuffled.count {
            shuffled = audioFiles.shuffled()
            // Make sure first of new shuffle != last of old shuffle
            if shuffled.first == lastPlayed && shuffled.count > 1 {
                shuffled.swapAt(0, shuffled.count - 1)
            }
            shuffleIndex = 0
        }

        let file = shuffled[shuffleIndex]
        shuffleIndex += 1
        lastPlayed = file

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        p.arguments = [file]
        try? p.run()
        audioProcess = p
    }

    @objc func testHit() { onHit() }

    @objc func quitApp() {
        unlink(socketPath)
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let d = AppDelegate()
app.delegate = d
app.run()
