import AppKit
import WebKit
import CryptoKit

final class Stage: WKWebView {
    var petMenu: NSMenu?
    @objc func exportPet() {
        evaluateJavaScript("JSON.stringify(pet)") { result, _ in
            guard let json = result as? String else { return }
            let picker = NSSavePanel()
            picker.nameFieldStringValue = "pet.json"
            if picker.runModal() == .OK, let url = picker.url {
                do { try json.write(to: url, atomically: true, encoding: .utf8) }
                catch { NSAlert(error: error).runModal() }
            }
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = petMenu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}
final class DragBridge: NSObject, WKScriptMessageHandler {
    weak var panel: NSPanel?
    private var timer: Timer?
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let action = message.body as? String else { return }
        stop()
        guard action == "begin", NSEvent.pressedMouseButtons & 1 != 0, let panel = panel else { return }
        let mouse = NSEvent.mouseLocation
        let origin = panel.frame.origin
        let tracking = Timer(timeInterval: 1.0/60, repeats:true) { [weak self, weak panel] _ in
            guard let panel = panel, panel.isVisible, NSEvent.pressedMouseButtons & 1 != 0 else {
                self?.stop()
                return
            }
            let current = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x:origin.x + current.x - mouse.x, y:origin.y + current.y - mouse.y))
        }
        timer = tracking
        RunLoop.main.add(tracking, forMode:.common)
    }
}
// Mirror confirmed numeric progress to the local library for subsequent CLI saves.
final class ProgressBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let raw = body["id"] as? String, let uuid = UUID(uuidString: raw),
              let revision = body["revision"] as? Int, revision >= 0,
              let key = body["key"] as? String,
              key.range(of: "^[a-z][a-z0-9-]{0,47}$", options: .regularExpression) != nil,
              let value = body["value"] as? Int, abs(Double(value)) < 9007199254740992 else { return }
        let root = ProcessInfo.processInfo.environment["PET_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PetStudio/client")
        let directory = root.appendingPathComponent("progress")
            .appendingPathComponent(uuid.uuidString.lowercased()).appendingPathComponent(String(revision))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try Data(String(value).utf8).write(to: directory.appendingPathComponent(key), options: .atomic)
        } catch { NSLog("无法保存插件进度") }
    }
}

// Only device-local session bindings can be opened by the native host.
final class SessionBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var panel: NSPanel?
    let identity: String
    init(panel: NSPanel, identity: String) { self.panel=panel; self.identity=identity }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let body=message.body as? [String:String] else { replyHandler(false,nil);return }
        if body["method"]=="layout", let panel=panel {
            var frame=panel.frame
            frame.size.height=body["visible"]=="yes" ? 286 : 170
            if let screen=panel.screen { frame.origin.y=min(frame.origin.y,screen.visibleFrame.maxY-frame.height) }
            panel.setFrame(frame,display:true)
            replyHandler(true,nil);return
        }
        guard let source=body["source"], let session=body["session"], let uuid=UUID(uuidString:identity),
              !source.contains("\0"), !session.contains("\0") else { replyHandler(false,nil);return }
        let key=SHA256.hash(data: Data((source+"\0"+session).utf8)).map { String(format:"%02x",$0) }.joined()
        let root=ProcessInfo.processInfo.environment["PET_HOME"].map { URL(fileURLWithPath:$0) }
            ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("PetStudio/client")
        let path=root.appendingPathComponent("session-links").appendingPathComponent(uuid.uuidString.lowercased()).appendingPathComponent(key)
        guard let text=try? String(contentsOf:path,encoding:.utf8), let url=URL(string:text),
              NSWorkspace.shared.urlForApplication(toOpen:url) != nil else { replyHandler(false,nil);return }
        switch body["method"] {
        case "available": replyHandler(true,nil)
        case "open": replyHandler(NSWorkspace.shared.open(url),nil)
        default: replyHandler(false,nil)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.main else { exit(1) }
let bundled = Bundle.main.url(forResource: "pet", withExtension: "html")
guard let file = bundled ?? CommandLine.arguments.dropFirst().first.map({ URL(fileURLWithPath: $0) }) else { exit(1) }
let panel = NSPanel(contentRect: NSRect(x: screen.visibleFrame.maxX-190,y: screen.visibleFrame.minY+45,width:170,height:170), styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
panel.isOpaque=false
panel.backgroundColor = .clear
panel.hasShadow=false
panel.level = .floating
panel.hidesOnDeactivate=false
panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
panel.title="啾咪桌宠"
let config=WKWebViewConfiguration()
let bridge=DragBridge()
bridge.panel=panel
config.userContentController.add(bridge,name:"petGrab")
config.userContentController.add(ProgressBridge(),name:"progress")
let petIdentity = bundled == nil ? file.deletingLastPathComponent().lastPathComponent : Bundle.main.bundleIdentifier?.components(separatedBy:".").last ?? ""
config.userContentController.addScriptMessageHandler(SessionBridge(panel:panel,identity:petIdentity), contentWorld:.page, name:"petSession")
let view=Stage(frame:panel.contentView!.bounds,configuration:config)
view.setValue(false, forKey:"drawsBackground")
panel.contentView=view
final class PetEvents: NSObject, WKNavigationDelegate {
    var onReady: (() -> Void)?
    var started = false
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !started else { return }
        started = true
        onReady?()
        DispatchQueue.global(qos: .utility).async {
            while let line = readLine() {
                guard line.utf8.count < 4096,
                      let data = line.data(using: .utf8),
                      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                DispatchQueue.main.async {
                    webView.callAsyncJavaScript("document.getElementById('stage').feedback.dispatch(event)", arguments: ["event": value], in: nil, in: .page, completionHandler: nil)
                }
            }
        }
    }
}
final class PetControls: NSObject, NSMenuDelegate, NSApplicationDelegate {
    let petPanel: NSPanel
    let stage: Stage
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let commands = NSMenu()
    let visibility = NSMenuItem()
    let settings = NSPanel(contentRect: NSRect(x:0,y:0,width:300,height:156),
                           styleMask:[.titled,.closable], backing:.buffered, defer:false)
    let defaults: UserDefaults

    init(panel: NSPanel, stage: Stage, identity: String) {
        self.petPanel = panel
        self.stage = stage
        defaults = UserDefaults(suiteName: "studio.jiumi.window." + identity) ?? .standard
        super.init()
        let name = Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String ?? "啾咪"
        item.button?.image = NSImage(systemSymbolName:"pawprint.fill", accessibilityDescription:name)
        if item.button?.image == nil { item.button?.title = "啾" }
        item.button?.toolTip = name
        commands.delegate = self
        visibility.action = #selector(togglePet)
        visibility.target = self
        commands.addItem(visibility)
        func add(_ title:String, _ action:Selector, _ target:AnyObject) {
            commands.addItem(withTitle:title,action:action,keyEquivalent:"").target = target
        }
        add("桌宠设置…", #selector(showSettings), self)
        add("恢复默认位置", #selector(resetPosition), self)
        add("导出角色包…", #selector(Stage.exportPet), stage)
        commands.addItem(.separator())
        add("退出桌宠", #selector(NSApplication.terminate(_:)), NSApp)
        item.menu = commands
        stage.petMenu = commands
        menuNeedsUpdate(commands)

        settings.title = name + " · 桌宠设置"
        settings.isReleasedWhenClosed = false
        let floating = NSButton(checkboxWithTitle:"保持桌宠置顶",target:self,action:#selector(setFloating(_:)))
        floating.frame = NSRect(x:20,y:76,width:245,height:26)
        floating.state = defaults.object(forKey:"floating") as? Bool == false ? .off : .on
        setFloating(floating)
        let label = NSTextField(labelWithString:"不透明度")
        label.frame = NSRect(x:20,y:33,width:70,height:22)
        let opacity = NSSlider(value:defaults.object(forKey:"opacity") as? Double ?? 1,
                               minValue:0.35,maxValue:1,target:self,action:#selector(setOpacity(_:)))
        opacity.frame = NSRect(x:92,y:32,width:184,height:24)
        opacity.isContinuous = true
        setOpacity(opacity)
        let nameToggle = NSButton(checkboxWithTitle:"显示名字",target:self,action:#selector(setNameVisible(_:)))
        nameToggle.frame = NSRect(x:20,y:112,width:245,height:26)
        nameToggle.state = defaults.bool(forKey:"showName") ? .on : .off
        for control in [floating as NSView,label,opacity,nameToggle] { settings.contentView?.addSubview(control) }
        settings.center()
    }
    func applyNameVisibility() {
        stage.callAsyncJavaScript("document.getElementById('label').hidden = !visible",
                                  arguments:["visible":defaults.bool(forKey:"showName")],
                                  in:nil,in:.page,completionHandler:nil)
    }
    @objc func setNameVisible(_ sender:NSButton) {
        defaults.set(sender.state == .on, forKey:"showName")
        applyNameVisibility()
    }
    @objc func setFloating(_ sender:NSButton) {
        petPanel.level = sender.state == .on ? .floating : .normal
        defaults.set(sender.state == .on,forKey:"floating")
    }
    @objc func setOpacity(_ sender:NSSlider) {
        petPanel.alphaValue = CGFloat(sender.doubleValue)
        defaults.set(sender.doubleValue,forKey:"opacity")
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        visibility.title = petPanel.isVisible ? "隐藏桌宠" : "显示桌宠"
    }
    @objc func togglePet() {
        if petPanel.isVisible { petPanel.orderOut(nil) } else { petPanel.orderFrontRegardless() }
        menuNeedsUpdate(commands)
    }
    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps:true)
        settings.makeKeyAndOrderFront(nil)
    }
    @objc func resetPosition() {
        guard let screen = petPanel.screen ?? NSScreen.main else { return }
        petPanel.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-190,y:screen.visibleFrame.minY+45))
        petPanel.orderFrontRegardless()
    }
    func applicationShouldHandleReopen(_ sender:NSApplication, hasVisibleWindows:Bool) -> Bool {
        petPanel.orderFrontRegardless()
        return true
    }
}
let controls = PetControls(panel:panel,stage:view,identity:bundled == nil ? file.deletingLastPathComponent().lastPathComponent : Bundle.main.bundleIdentifier ?? "local")
app.delegate = controls
let events = PetEvents()
events.onReady = { controls.applyNameVisibility() }
view.navigationDelegate = events
view.loadFileURL(file,allowingReadAccessTo:file.deletingLastPathComponent())
panel.orderFrontRegardless()
app.run()
