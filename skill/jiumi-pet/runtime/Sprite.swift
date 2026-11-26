import AppKit
import WebKit
import CryptoKit
import Carbon.HIToolbox

struct PetShortcut: Equatable {
    // Hardware codes keep a saved binding stable across input methods.
    static let codes: [Character:UInt32] = [
        "A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,
        "Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,
        "6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"O":31,"U":32,"I":34,"P":35,
        "L":37,"J":38,"K":40,"N":45,"M":46
    ]
    let key: Character
    let flags: UInt32
    static let modifiers: [(Character,UInt32,NSEvent.ModifierFlags)] =
        [("⌃",UInt32(controlKey),.control),("⌥",UInt32(optionKey),.option),
         ("⇧",UInt32(shiftKey),.shift),("⌘",UInt32(cmdKey),.command)]
    var label: String {
        String(Self.modifiers.filter { flags & $0.1 != 0 }.map { $0.0 }) + String(key)
    }
    init?(_ text: String) {
        let chars = text.trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
        guard let key = chars.last, Self.codes[key] != nil else { return nil }
        var flags:UInt32 = 0
        for char in chars.dropLast() {
            guard let mod = Self.modifiers.first(where: { $0.0 == char }) else { return nil }
            flags |= mod.1
        }
        guard flags & ~UInt32(shiftKey) != 0 else { return nil }
        self.key = key
        self.flags = flags
    }
    init?(event: NSEvent) {
        guard let pair = Self.codes.first(where: { $0.value == UInt32(event.keyCode) }) else { return nil }
        self.init(String(Self.modifiers.filter { event.modifierFlags.contains($0.2) }.map { $0.0 }) + String(pair.key))
    }
}

final class VisibilityHotKey {
    private var handler:EventHandlerRef?
    private var binding:EventHotKeyRef?
    private(set) var active:PetShortcut?
    var pressed: (() -> Void)?
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context = context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x4A69756D else { return OSStatus(eventNotHandledErr) }
            Unmanaged<VisibilityHotKey>.fromOpaque(context).takeUnretainedValue().pressed?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func replace(with shortcut:PetShortcut?) -> Bool {
        if shortcut == active { return true }
        var candidate:EventHotKeyRef?
        if let shortcut = shortcut {
            guard handler != nil, let code = PetShortcut.codes[shortcut.key],
                  RegisterEventHotKey(code, shortcut.flags, EventHotKeyID(signature:0x4A69756D,id:code),
                    GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &candidate) == noErr else { return false }
        }
        if let previous = binding { UnregisterEventHotKey(previous) }
        binding = candidate
        active = shortcut
        return true
    }
    deinit {
        if let binding = binding { UnregisterEventHotKey(binding) }
        if let handler = handler { RemoveEventHandler(handler) }
    }
}

final class SettingsPanel: NSPanel {
    var record: ((NSEvent) -> Void)?
    override func sendEvent(_ event:NSEvent) {
        if event.type == .keyDown, let record = record { record(event); return }
        super.sendEvent(event)
    }
    override func resignKey() { record = nil; super.resignKey() }
}

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
            frame.size.height=(body["visible"]=="yes" ? 286 : 170) * frame.width / 170
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
final class PetControls: NSObject, NSMenuDelegate, NSApplicationDelegate, NSWindowDelegate {
    let petPanel: NSPanel
    let stage: Stage
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let commands = NSMenu()
    let context = NSMenu()
    let interactions = NSMenu()
    let hotKey = VisibilityHotKey()
    let shortcutField = NSTextField()
    let feedback = NSTextField(wrappingLabelWithString:"")
    let remember = NSButton(checkboxWithTitle:"记住桌宠位置",target:nil,action:nil)
    var restoreControls: (() -> Void)?
    let name = Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String ?? "桌宠"
    let settings = SettingsPanel(contentRect: NSRect(x:0,y:0,width:390,height:365),
                           styleMask:[.titled,.closable], backing:.buffered, defer:false)
    let defaults: UserDefaults

    init(panel: NSPanel, stage: Stage, identity: String) {
        self.petPanel = panel
        self.stage = stage
        defaults = UserDefaults(suiteName: "studio.jiumi.window." + identity) ?? .standard
        super.init()
        item.button?.image = NSImage(systemSymbolName:"pawprint.fill", accessibilityDescription:name)
        if item.button?.image == nil { item.button?.title = "啾" }
        item.button?.toolTip = name
        for menu in [commands,context] {
            menu.delegate = self
            for (title, action) in [("显示"+name,#selector(togglePet)),("移回当前屏幕",#selector(resetPosition)),
                                    ("桌宠设置…",#selector(showSettings))] {
                menu.addItem(withTitle:title,action:action,keyEquivalent:"").target = self
            }
            menu.addItem(withTitle:"导出角色包…",action:#selector(Stage.exportPet),keyEquivalent:"").target = stage
            menu.addItem(.separator())
            menu.addItem(withTitle:"退出"+name,action:#selector(NSApplication.terminate(_:)),keyEquivalent:"").target = NSApp
        }
        item.menu = commands
        stage.petMenu = context
        settings.title = name + " · 桌宠设置"
        settings.isReleasedWhenClosed = false
        func place(_ view:NSView,_ x:Int,_ y:Int,_ w:Int,_ h:Int) {
            view.frame = NSRect(x:x,y:y,width:w,height:h)
            settings.contentView?.addSubview(view)
        }
        func slider(_ label:String,_ key:String,_ initial:Double,_ min:Double,_ max:Double,_ y:Int,_ action:Selector) -> NSSlider {
            place(NSTextField(labelWithString:label),20,y,72,22)
            let value = defaults.object(forKey:key) as? Double ?? initial
            let control = NSSlider(value:value,minValue:min,maxValue:max,target:self,action:action)
            control.isContinuous = true
            control.setAccessibilityLabel(label)
            place(control,100,y,250,24)
            return control
        }
        let size = slider("角色大小","size",1,0.65,1.75,318,#selector(setSize(_:)))
        setSize(size)
        let opacity = slider("不透明度","opacity",1,0.35,1,282,#selector(setOpacity(_:)))
        setOpacity(opacity)
        let floating = NSButton(checkboxWithTitle:"保持桌宠置顶",target:self,action:#selector(setFloating(_:)))
        floating.state = defaults.object(forKey:"floating") as? Bool == false ? .off : .on
        setFloating(floating)
        place(floating,20,245,165,25)
        let nameToggle = NSButton(checkboxWithTitle:"显示名字",target:self,action:#selector(setNameVisible(_:)))
        nameToggle.state = defaults.bool(forKey:"showName") ? .on : .off
        place(nameToggle,195,245,150,25)
        remember.state = defaults.object(forKey:"rememberPosition") as? Bool == false ? .off : .on
        remember.target = self
        remember.action = #selector(setRemember)
        place(remember,20,210,185,25)
        if remember.state == .on, let point = defaults.string(forKey:"position") {
            petPanel.setFrameOrigin(NSPointFromString(point))
        }
        ensureOnScreen()
        petPanel.delegate = self
        place(NSTextField(labelWithString:"全局快捷键 · 显示或隐藏"+name),20,165,350,22)
        shortcutField.placeholderString = "未绑定"
        shortcutField.setAccessibilityLabel("显隐快捷键")
        place(shortcutField,20,123,120,25)
        for (i,entry) in [("录入",#selector(recordKey)),("应用",#selector(applyKey)),("清除",#selector(clearKey))].enumerated() {
            place(NSButton(title:entry.0,target:self,action:entry.1),145+i*73,120,72,30)
        }
        place(NSTextField(wrappingLabelWithString:"录入组合键，或输入如 ⌃⌥K 的组合再点应用。"),20,73,350,35)
        place(feedback,20,12,235,52)
        place(NSButton(title:"重置设置…",target:self,action:#selector(resetSettings)),255,20,110,30)
        restoreControls = { [weak self] in
            guard let self = self else { return }
            size.doubleValue = 1
            opacity.doubleValue = 1
            floating.state = .on
            nameToggle.state = .off
            self.remember.state = .on
            self.setSize(size)
            self.setOpacity(opacity)
            self.setFloating(floating)
            self.setNameVisible(nameToggle)
            self.setRemember()
            self.clearKey()
            self.resetPosition()
            self.feedback.stringValue = "已恢复桌宠设置。"
        }
        hotKey.pressed = { [weak self] in self?.togglePet() }
        if let saved = defaults.string(forKey:"shortcut") {
            shortcutField.stringValue = saved
            applyKey()
        }
        settings.center()
    }
    func loadPluginMenu() {
        stage.evaluateJavaScript("document.getElementById('stage').feedback.menuItems") { result, _ in
            guard let items = result as? [[String:String]] else { return }
            guard !items.isEmpty else { return }
            let group = NSMenuItem(title:"互动",action:nil,keyEquivalent:"")
            group.submenu = self.interactions
            self.commands.insertItem(group,at:2)
            self.context.insertItem(.separator(),at:0)
            for (index,entry) in items.enumerated() {
                guard let label = entry["label"], let event = entry["event"] else { continue }
                let item = NSMenuItem(title:label,action:#selector(self.selectPluginItem(_:)),keyEquivalent:"")
                item.target = self
                item.representedObject = event
                self.context.insertItem(item,at:index)
                self.interactions.addItem(item.copy() as! NSMenuItem)
            }
        }
    }
    @objc func selectPluginItem(_ sender:NSMenuItem) {
        guard let event = sender.representedObject as? String else { return }
        showPet(true)
        stage.callAsyncJavaScript("return document.getElementById('stage').feedback.selectMenu(event)",
                                  arguments:["event":event], in:nil, in:.page, completionHandler:nil)
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
    @objc func resetSettings() {
        let alert = NSAlert()
        alert.messageText = "恢复"+name+"的桌面设置？"
        alert.informativeText = "尺寸、位置、外观和显隐快捷键将恢复默认。"
        alert.addButton(withTitle:"取消")
        alert.addButton(withTitle:"恢复默认")
        alert.beginSheetModal(for:settings) { response in
            if response == .alertSecondButtonReturn { self.restoreControls?() }
        }
    }
    @objc func recordKey() {
        feedback.stringValue = "按组合键录入，Esc 取消。"
        settings.record = { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == 53 {
                self.settings.record = nil
                self.feedback.stringValue = ""
            } else if let shortcut = PetShortcut(event:event) {
                self.settings.record = nil
                self.shortcutField.stringValue = shortcut.label
                self.applyKey()
            } else {
                self.feedback.stringValue = "请用 ⌃、⌥ 或 ⌘ 搭配字母或数字，可加 ⇧。"
            }
        }
    }
    @objc func applyKey() {
        settings.record = nil
        guard let key = PetShortcut(shortcutField.stringValue) else {
            feedback.stringValue = "请输入有效的组合键。"; return
        }
        if hotKey.replace(with:key) {
            defaults.set(key.label,forKey:"shortcut")
            shortcutField.stringValue = key.label
            feedback.stringValue = "已绑定 " + key.label
        } else {
            feedback.stringValue = "组合键已占用或不可用。" + (hotKey.active.map {"当前仍使用 " + $0.label} ?? "可通过菜单栏召回。")
        }
    }
    @objc func clearKey() {
        settings.record = nil
        _ = hotKey.replace(with:nil)
        defaults.removeObject(forKey:"shortcut")
        shortcutField.stringValue = ""
        feedback.stringValue = "已清除快捷键。"
    }
    @objc func setRemember() {
        defaults.set(remember.state == .on,forKey:"rememberPosition")
        if remember.state == .on { savePosition() } else { defaults.removeObject(forKey:"position") }
    }
    func savePosition() {
        if remember.state == .on { defaults.set(NSStringFromPoint(petPanel.frame.origin),forKey:"position") }
    }
    func windowDidMove(_ notification:Notification) { savePosition() }
    func ensureOnScreen() {
        guard let screen = petPanel.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame, frame = petPanel.frame
        petPanel.setFrameOrigin(NSPoint(x:max(area.minX,min(frame.minX,area.maxX-frame.width)),
                                        y:max(area.minY,min(frame.minY,area.maxY-frame.height))))
    }
    func applicationDidChangeScreenParameters(_ notification:Notification) { ensureOnScreen() }
    @objc func setSize(_ sender:NSSlider) {
        let zoom = CGFloat(sender.doubleValue)
        let frame = petPanel.frame
        stage.pageZoom = zoom
        petPanel.setContentSize(NSSize(width:170*zoom,height:frame.height/frame.width*170*zoom))
        defaults.set(zoom,forKey:"size")
        ensureOnScreen()
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.items.first(where: {$0.action == #selector(togglePet)})?.title = (petPanel.isVisible ? "隐藏" : "显示") + name
    }
    func showPet(_ visible:Bool) {
        if visible { petPanel.orderFrontRegardless() } else { petPanel.orderOut(nil) }
        stage.callAsyncJavaScript("document.getElementById('stage').feedback?.setVisible(visible)",
                                  arguments:["visible":visible],in:nil,in:.page,completionHandler:nil)
    }
    @objc func togglePet() { showPet(!petPanel.isVisible) }
    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps:true)
        settings.makeKeyAndOrderFront(nil)
    }
    @objc func resetPosition() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        petPanel.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-petPanel.frame.width-20,y:screen.visibleFrame.minY+45))
        showPet(true)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication, hasVisibleWindows:Bool) -> Bool {
        showPet(true)
        return true
    }
}
let controls = PetControls(panel:panel,stage:view,identity:bundled == nil ? file.deletingLastPathComponent().lastPathComponent : Bundle.main.bundleIdentifier ?? "local")
app.delegate = controls
let events = PetEvents()
events.onReady = { controls.applyNameVisibility(); controls.loadPluginMenu() }
view.navigationDelegate = events
view.loadFileURL(file,allowingReadAccessTo:file.deletingLastPathComponent())
panel.orderFrontRegardless()
app.run()
