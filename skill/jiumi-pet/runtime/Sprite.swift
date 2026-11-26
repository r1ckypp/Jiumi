import AppKit
import ServiceManagement
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
panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenNone]
panel.title="啾咪桌宠"
let config=WKWebViewConfiguration()
let bridge=DragBridge()
bridge.panel=panel
config.userContentController.add(bridge,name:"petGrab")
config.userContentController.add(ProgressBridge(),name:"progress")
let petIdentity = bundled == nil ? file.deletingLastPathComponent().lastPathComponent : Bundle.main.bundleIdentifier?.components(separatedBy:".").last ?? ""
config.userContentController.addScriptMessageHandler(SessionBridge(panel:panel,identity:petIdentity), contentWorld:.page, name:"petSession")
let preferenceID=bundled == nil ? petIdentity : Bundle.main.bundleIdentifier ?? "local"
let startupPreferences=UserDefaults(suiteName:"studio.jiumi.window." + preferenceID)
if let overrides=startupPreferences?.dictionary(forKey:"pluginOverrides") as? [String:Bool],
   let data=try? JSONEncoder().encode(overrides), let json=String(data:data,encoding:.utf8) {
    config.userContentController.addUserScript(WKUserScript(source:"window.petPluginOverrides="+json,injectionTime:.atDocumentStart,forMainFrameOnly:true))
}
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
    let passThrough = NSButton(checkboxWithTitle:"鼠标穿透",target:nil,action:nil)
    let avoidFullscreen = NSButton(checkboxWithTitle:"全屏时避让",target:nil,action:nil)
    let loginItem = NSButton(checkboxWithTitle:"登录时启动",target:nil,action:nil)
    let manager = NSPanel(contentRect:NSRect(x:0,y:0,width:400,height:220),
                          styleMask:[.titled,.closable],backing:.buffered,defer:false)
    let pluginChoice = NSPopUpButton()
    let pluginSwitch = NSButton(checkboxWithTitle:"启用插件",target:nil,action:nil)
    let actionChoice = NSPopUpButton()
    let actionShown = NSButton(checkboxWithTitle:"显示在菜单中",target:nil,action:nil)
    let alias = NSTextField()
    let moveUp = NSButton(title:"上移",target:nil,action:nil)
    let moveDown = NSButton(title:"下移",target:nil,action:nil)
    var sleeping=false
    var pluginRows = [[String:Any]]()
    var availableActions = [[String:String]]()
    var actionRows = [[String:String]]()
    var commandGroup:NSMenuItem?
    var insertedItems = [NSMenuItem]()
    let passCommand = NSMenuItem()
    var restoreControls: (() -> Void)?
    let name = Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String ?? "桌宠"
    let settings = SettingsPanel(contentRect: NSRect(x:0,y:0,width:390,height:457),
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
        passCommand.target = self
        passCommand.action = #selector(togglePassThrough)
        commands.insertItem(passCommand,at:2)
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
        loginItem.target=self; loginItem.action = #selector(changeLoginItem)
        refreshLoginItem()
        place(loginItem,20,415,170,26)
        let manage=NSButton(title:"插件与互动菜单…",target:self,action:#selector(openManager))
        place(manage,195,413,178,30)
        configureManager()
        passThrough.state = defaults.bool(forKey:"passThrough") ? .on : .off
        passThrough.target = self
        passThrough.action = #selector(applyPassThrough)
        applyPassThrough()
        place(passThrough,20,367,165,25)
        avoidFullscreen.state = defaults.object(forKey:"avoidFullscreen") as? Bool == false ? .off : .on
        avoidFullscreen.target = self
        avoidFullscreen.action = #selector(applyFullscreenPolicy)
        applyFullscreenPolicy()
        place(avoidFullscreen,195,367,175,25)
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
            self.passThrough.state = .off
            self.applyPassThrough()
            self.avoidFullscreen.state = .on
            self.applyFullscreenPolicy()
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
        let workspaceEvents=NSWorkspace.shared.notificationCenter
        workspaceEvents.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
        workspaceEvents.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
        settings.center()
    }
    func refreshLoginItem() {
        loginItem.isEnabled = false
        loginItem.state = .off
        if #available(macOS 13.0,*), bundled != nil {
            loginItem.isEnabled = true
            switch SMAppService.mainApp.status {
            case .enabled: loginItem.state = .on
            case .requiresApproval: loginItem.state = .mixed
            default: break
            }
        }
        loginItem.toolTip = loginItem.isEnabled ? nil : "需要 macOS 13 或更高版本的独立应用。"
    }
    @objc func changeLoginItem() {
        guard #available(macOS 13.0,*), bundled != nil else { return }
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .requiresApproval:
                let alert=NSAlert()
                alert.messageText="此登录项等待系统批准"
                alert.addButton(withTitle:"打开系统设置")
                alert.addButton(withTitle:"取消登录项")
                alert.addButton(withTitle:"返回")
                switch alert.runModal() {
                case .alertFirstButtonReturn: SMAppService.openSystemSettingsLoginItems()
                case .alertSecondButtonReturn: try service.unregister()
                default: break
                }
            case .enabled: try service.unregister()
            default: try service.register()
            }
            feedback.stringValue = service.status == .requiresApproval ? "请在系统设置的登录项中允许此应用。" : ""
        } catch {
            feedback.stringValue = "登录项设置失败：" + error.localizedDescription
        }
        refreshLoginItem()
    }
    func configureManager() {
        manager.title = name + " · 插件与互动菜单"
        manager.isReleasedWhenClosed = false
        func place(_ v:NSView,_ x:Int,_ y:Int,_ w:Int,_ h:Int) {
            v.frame = NSRect(x:x,y:y,width:w,height:h)
            manager.contentView?.addSubview(v)
        }
        pluginChoice.target=self; pluginChoice.action = #selector(selectPlugin)
        pluginSwitch.target=self; pluginSwitch.action = #selector(changePlugin)
        actionChoice.target=self; actionChoice.action = #selector(selectAction)
        actionShown.target=self; actionShown.action = #selector(changeAction)
        alias.setAccessibilityLabel("菜单名称")
        alias.placeholderString = "使用原名称"
        alias.target=self; alias.action = #selector(changeAction)
        moveUp.target=self; moveUp.action = #selector(moveAction(_:))
        moveDown.target=self; moveDown.action = #selector(moveAction(_:))
        place(pluginChoice,16,168,245,30); place(pluginSwitch,268,168,120,30)
        place(NSTextField(labelWithString:"已启用插件的互动菜单"),20,132,320,22)
        place(actionChoice,16,95,245,30); place(actionShown,268,95,125,30)
        place(NSTextField(labelWithString:"菜单名称"),20,59,70,22)
        place(alias,95,58,170,24)
        let save=NSButton(title:"应用名称",target:self,action:#selector(changeAction))
        place(save,270,55,110,30)
        place(moveUp,16,12,86,32); place(moveDown,105,12,86,32)
        place(NSButton(title:"恢复默认菜单",target:self,action:#selector(resetMenu)),230,12,149,32)
        manager.center()
    }
    @objc func resetMenu() {
        for key in ["actionLabels","hiddenActions","actionOrder"] { defaults.removeObject(forKey:key) }
        renderMenus()
    }
    @objc func openManager() {
        manager.makeKeyAndOrderFront(nil)
        loadPluginMenu()
    }
    func loadPluginMenu() {
        let script = """
        ({plugins:[...(pet.modules || []),...rules].map(m=>({id:m.id,name:m.name,version:m.version,enabled:pet.plugins.includes(m.id)})),
          actions:stage.feedback.menuItems})
        """
        stage.evaluateJavaScript(script) { result,_ in
            guard let data=result as? [String:Any], let plugins=data["plugins"] as? [[String:Any]],
                  let actions=data["actions"] as? [[String:String]] else { return }
            self.pluginRows=plugins
            self.availableActions=actions
            self.renderMenus()
        }
    }
    func renderMenus() {
        let order=defaults.stringArray(forKey:"actionOrder") ?? []
        let hidden=defaults.stringArray(forKey:"hiddenActions") ?? []
        let labels=defaults.dictionary(forKey:"actionLabels") as? [String:String] ?? [:]
        let previousPlugin=pluginChoice.selectedItem?.representedObject as? String
        let previousAction=actionChoice.selectedItem?.representedObject as? String
        let ordered=order.compactMap { id in availableActions.first { $0["event"]==id } }
            + availableActions.filter { !order.contains($0["event"] ?? "") }
        actionRows=ordered
        pluginChoice.removeAllItems()
        for plugin in pluginRows {
            guard let id=plugin["id"] as? String, let title=plugin["name"] as? String else { continue }
            let item=NSMenuItem(title:title+" · v"+String(plugin["version"] as? Int ?? 1),action:nil,keyEquivalent:"")
            item.representedObject=id
            pluginChoice.menu?.addItem(item)
            if previousPlugin==id { pluginChoice.select(item) }
        }
        if pluginRows.isEmpty { pluginChoice.addItem(withTitle:"尚未安装插件") }
        selectPlugin()
        for item in insertedItems { context.removeItem(item) }
        insertedItems.removeAll()
        if let group=commandGroup { commands.removeItem(group); commandGroup=nil }
        interactions.removeAllItems()
        actionChoice.removeAllItems()
        for action in ordered {
            guard let id=action["event"],let title=action["label"] else { continue }
            let label=labels[id] ?? title
            let choice=NSMenuItem(title:label,action:nil,keyEquivalent:"")
            choice.representedObject=id
            actionChoice.menu?.addItem(choice)
            if previousAction==id { actionChoice.select(choice) }
            if hidden.contains(id) { continue }
            let item=NSMenuItem(title:label,action:#selector(selectPluginItem(_:)),keyEquivalent:"")
            item.target=self; item.representedObject=id
            context.insertItem(item,at:insertedItems.count)
            insertedItems.append(item)
            interactions.addItem(item.copy() as! NSMenuItem)
        }
        if !insertedItems.isEmpty {
            let separator=NSMenuItem.separator()
            context.insertItem(separator,at:insertedItems.count)
            insertedItems.append(separator)
            let group=NSMenuItem(title:"互动",action:nil,keyEquivalent:"")
            group.submenu=interactions
            commands.insertItem(group,at:2)
            commandGroup=group
        }
        if ordered.isEmpty { actionChoice.addItem(withTitle:"暂无互动菜单项") }
        selectAction()
    }
    @objc func selectPlugin() {
        let id=pluginChoice.selectedItem?.representedObject as? String
        pluginSwitch.isEnabled=id != nil
        let current=pluginRows.first { $0["id"] as? String==id }
        pluginSwitch.state=current?["enabled"] as? Bool == true ? .on : .off
    }
    @objc func changePlugin() {
        guard let id=pluginChoice.selectedItem?.representedObject as? String else { return }
        let enabled=pluginSwitch.state == .on
        pluginSwitch.isEnabled=false
        stage.callAsyncJavaScript("return stage.feedback.setPlugin(id,enabled)",arguments:["id":id,"enabled":enabled],in:nil,in:.page) { result in
            if case .success(let response)=result, response as? Bool == true {
                var overrides=self.defaults.dictionary(forKey:"pluginOverrides") ?? [:]
                overrides[id]=enabled
                self.defaults.set(overrides,forKey:"pluginOverrides")
            }
            self.loadPluginMenu()
        }
    }
    @objc func selectAction() {
        let id=actionChoice.selectedItem?.representedObject as? String
        let index=actionChoice.indexOfSelectedItem
        alias.isEnabled=id != nil; actionShown.isEnabled=id != nil
        moveUp.isEnabled=id != nil && index>0
        moveDown.isEnabled=id != nil && index+1<actionRows.count
        alias.stringValue=id.flatMap { defaults.dictionary(forKey:"actionLabels")?[$0] as? String } ?? ""
        actionShown.state=id.map { !(defaults.stringArray(forKey:"hiddenActions") ?? []).contains($0) } == true ? .on : .off
    }
    @objc func changeAction() {
        guard let id=actionChoice.selectedItem?.representedObject as? String else { return }
        var labels=defaults.dictionary(forKey:"actionLabels") as? [String:String] ?? [:]
        let title=String(alias.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
        labels[id]=title.isEmpty ? nil : title
        defaults.set(labels,forKey:"actionLabels")
        var hidden=Set(defaults.stringArray(forKey:"hiddenActions") ?? [])
        if actionShown.state == .on { hidden.remove(id) } else { hidden.insert(id) }
        defaults.set(Array(hidden),forKey:"hiddenActions")
        renderMenus()
    }
    @objc func moveAction(_ sender:NSButton) {
        let index=actionChoice.indexOfSelectedItem
        let next=index+(sender === moveUp ? -1 : 1)
        guard actionRows.indices.contains(index),actionRows.indices.contains(next) else { return }
        actionRows.swapAt(index,next)
        defaults.set(actionRows.compactMap { $0["event"] },forKey:"actionOrder")
        renderMenus()
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
    @objc func applyPassThrough() {
        let enabled = passThrough.state == .on
        petPanel.ignoresMouseEvents = enabled
        passCommand.title = enabled ? "关闭鼠标穿透" : "开启鼠标穿透"
        defaults.set(enabled,forKey:"passThrough")
    }
    @objc func togglePassThrough() {
        passThrough.state = passThrough.state == .on ? .off : .on
        applyPassThrough()
    }
    @objc func applyFullscreenPolicy() {
        let enabled = avoidFullscreen.state == .on
        petPanel.collectionBehavior = [.canJoinAllSpaces, enabled ? .fullScreenNone : .fullScreenAuxiliary]
        defaults.set(enabled,forKey:"avoidFullscreen")
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.items.first(where: {$0.action == #selector(togglePet)})?.title = (petPanel.isVisible ? "隐藏" : "显示") + name
    }
    @objc func willSleep() {
        sleeping=true
        syncPlayerVisibility()
    }
    @objc func didWake() {
        sleeping=false
        syncPlayerVisibility()
    }
    func syncPlayerVisibility() {
        stage.callAsyncJavaScript("document.getElementById('stage').feedback?.setVisible(visible)",
                                  arguments:["visible":petPanel.isVisible && !sleeping],in:nil,in:.page,completionHandler:nil)
    }
    func showPet(_ visible:Bool) {
        if visible { petPanel.orderFrontRegardless() } else { petPanel.orderOut(nil) }
        syncPlayerVisibility()
    }
    @objc func togglePet() { showPet(!petPanel.isVisible) }
    @objc func showSettings() {
        refreshLoginItem()
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
let controls = PetControls(panel:panel,stage:view,identity:preferenceID)
app.delegate = controls
let events = PetEvents()
events.onReady = { controls.applyNameVisibility(); controls.loadPluginMenu() }
view.navigationDelegate = events
view.loadFileURL(file,allowingReadAccessTo:file.deletingLastPathComponent())
panel.orderFrontRegardless()
app.run()
