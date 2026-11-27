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
    private var noticeVisible=false, speechVisible=false
    init(panel: NSPanel, identity: String) { self.panel=panel; self.identity=identity }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let body=message.body as? [String:String] else { replyHandler(false,nil);return }
        if ["layout","speechLayout"].contains(body["method"] ?? ""), let panel=panel {
            if body["method"]=="layout" { noticeVisible=body["visible"]=="yes" }
            else { speechVisible=body["visible"]=="yes" }
            var frame=panel.frame
            frame.size.height=(noticeVisible ? 286 : (speechVisible ? 280 : 170)) * frame.width / 170
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

var clientLanguage="zh-CN"
let englishText:[String:String]=[
    "无法保存插件进度":"Could not save plugin progress",
    "啾咪桌宠":"Jiumi Desktop Pet",
    "记住桌宠位置":"Remember window position",
    "鼠标穿透":"Click through pet",
    "全屏时避让":"Avoid full-screen apps",
    "登录时启动":"Open at login",
    "外观":"Appearance",
    "桌宠窗口":"Pet Window",
    "输入与权限":"Input & Permissions",
    "快捷键":"Shortcuts",
    "插件与互动":"Plugins & Interactions",
    "应用与系统":"App & System",
    "关于":"About",
    "主题 深色 浅色 名字 大小 缩放 不透明度 待机 动画 随机 间隔 频率":"theme dark light name size zoom opacity idle animation random interval frequency",
    "置顶 全屏 避让 位置 召回 穿透":"always on top full screen position recall click through",
    "跨应用 陪打字 输入监控 授权 隐私 键盘":"typing input monitoring permission privacy keyboard",
    "录入 显示 隐藏 热键":"record show hide hotkey",
    "菜单 名称 插件 顺序":"menu name plugins order",
    "版本 当前角色 导出":"version current character export",
    "跨应用陪打字":"Type along across apps",
    "尚未安装插件":"No plugins installed",
    "显示在菜单中":"Show in menu",
    "上移":"Move up",
    "下移":"Move down",
    "啾":"J",
    "显示":"Show ",
    "桌宠设置…":"Pet Settings…",
    "退出":"Quit ",
    " 设置":" Settings",
    "设置窗口主题":"Settings theme",
    "跟随系统":"System",
    "浅色":"Light",
    "深色":"Dark",
    "角色大小":"Pet size",
    "窗口不透明度":"Window opacity",
    "显示角色名字":"Show pet name",
    "待机动作间隔":"Idle action interval",
    " 秒":" s",
    "最短待机间隔":"Minimum idle interval",
    "最长待机间隔":"Maximum idle interval",
    "至":"to",
    "每轮休息时随机选取等待时间。":"The wait is randomized after each idle action.",
    "保持桌宠置顶":"Keep pet on top",
    "移回当前屏幕":"Move to this screen",
    "开启后，角色会跟随其他应用里的敲击节奏。输入的文字和按键内容不会传给角色。":"The pet follows your typing rhythm in other apps. It receives timing only.",
    "输入监控权限":"Input Monitoring",
    "打开系统输入监控设置":"Open Input Monitoring",
    "显示或隐藏桌宠":"Show or hide pet",
    "未绑定":"Unassigned",
    "显隐快捷键":"Visibility shortcut",
    "录入":"Record",
    "应用":"Apply",
    "清除":"Clear",
    "点击录入后按下组合键，或输入如 ⌃⌥K 的组合再点应用。":"Record a key combination, or type a shortcut such as ⌃⌥K and click Apply.",
    "恢复桌面设置…":"Reset window settings…",
    "客户端版本":"Client version",
    "当前角色":"Current pet",
    "导出角色包…":"Export pet…",
    "8 秒":"8 s",
    "20 秒":"20 s",
    "已恢复桌宠设置。":"Window settings restored.",
    "搜索设置":"Search settings",
    "没有匹配的设置":"No matching settings",
    "已允许":"Allowed",
    "未授权":"Not authorized",
    "请先启用支持陪打字的角色插件":"Enable a typing plugin first.",
    "需要 macOS 13 或更高版本的独立应用。":"Requires a standalone app on macOS 13 or later.",
    "此登录项等待系统批准":"This login item needs approval",
    "打开系统设置":"Open System Settings",
    "取消登录项":"Remove login item",
    "返回":"Back",
    "请在系统设置的登录项中允许此应用。":"Allow this app in Login Items in System Settings.",
    "登录项设置失败：":"Could not update login item: ",
    "已安装插件":"Installed plugins",
    "插件":"Plugin",
    "版本":"Version",
    "启用":"Enable ",
    "菜单名称":"Menu name",
    "使用原名称":"Use original name",
    "已启用插件的互动菜单":"Interaction menu",
    "应用名称":"Apply name",
    "恢复默认菜单":"Reset menu",
    "互动":"Interactions",
    "暂无互动菜单项":"No menu actions",
    "插件信息":"Plugin information",
    "气泡台词":"Speech bubbles",
    "互动动作":"Interaction",
    "会话提醒":"Session notice",
    "本地模块":"Local module",
    "事件规则":"Event rule",
    "敲键时，角色会跟随输入节奏做出动作。":"The pet moves in time with your keystrokes.",
    "已启用":"Enabled",
    "已关闭":"Disabled",
    "类型　":"Type    ",
    "版本　v":"Version    v",
    "状态　":"Status    ",
    "触发事件　":"Events    ",
    "插件标识　":"Plugin ID    ",
    "完成":"Done",
    "查看":"View ",
    "的信息":" details",
    "恢复":"Reset ",
    "的桌面设置？":" window settings?",
    "尺寸、位置、外观和显隐快捷键将恢复默认。":"Size, position, appearance and the visibility shortcut will return to their defaults.",
    "取消":"Cancel",
    "恢复默认":"Restore defaults",
    "按组合键录入，Esc 取消。":"Press a shortcut, or Esc to cancel.",
    "请用 ⌃、⌥ 或 ⌘ 搭配字母或数字，可加 ⇧。":"Combine ⌃, ⌥ or ⌘ with a letter or number. ⇧ is optional.",
    "请输入有效的组合键。":"Enter a valid shortcut.",
    "已绑定 ":"Assigned ",
    "组合键已占用或不可用。":"Shortcut unavailable. ",
    "当前仍使用 ":"Current shortcut: ",
    "可通过菜单栏召回。":"Use the menu bar to show the pet.",
    "已清除快捷键。":"Shortcut cleared.",
    "允许 ":"Allow ",
    " 使用输入监控":" to monitor input",
    "在系统设置的「隐私与安全性 → 输入监控」中允许 ":"In System Settings → Privacy & Security → Input Monitoring, enable ",
    "。授权后重新打开客户端，再开启陪打字。角色只接收敲击节奏。":". Reopen the app and enable typing. Only timing is shared with the pet.",
    "打开输入监控":"Open Input Monitoring",
    "稍后":"Later",
    "暂时无法接收敲击，请重开客户端后重试。":"Input is unavailable. Reopen the app and try again.",
    "隐藏":"Hide ",
    "界面语言":"Interface language",
    "语言":"language",
    "陪打字":"Type Along",
    "随机气泡":"Random Speech",
    "喂一口":"Feed a bite",
    "启动 登录 重置 默认 语言":"startup login reset defaults language English Chinese"
]
func tr(_ key:String) -> String { clientLanguage=="en" ? englishText[key] ?? key : key }

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
let seedLanguage=Bundle.main.object(forInfoDictionaryKey:"JiumiDefaultLanguage") as? String ?? ProcessInfo.processInfo.environment["JIUMI_DEFAULT_LANGUAGE"] ?? "zh-CN"
let startupLanguage=(startupPreferences?.string(forKey:"clientLanguage") ?? seedLanguage)=="en" ? "en" : "zh-CN"
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
// Listen-only tap. Only a stroke reaches the page, never a key code or text.
final class TypingInput {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    let stroke: () -> Void

    init(stroke: @escaping () -> Void) { self.stroke = stroke }

    func start() -> Bool {
        if tap != nil { return true }
        guard CGPreflightListenEventAccess(),
              let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                options: .listenOnly, eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
                callback: { _, type, event, context in
                    guard let context = context else { return nil }
                    let input = Unmanaged<TypingInput>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout, let port = input.tap {
                        CGEvent.tapEnable(tap: port, enable: true)
                    } else if type == .keyDown, event.flags.intersection([.maskCommand,.maskControl,.maskAlternate]).isEmpty,
                              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        input.stroke()
                    }
                    return nil
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }
    deinit { stop() }
}

final class PetControls: NSObject, NSMenuDelegate, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
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
    let pageTitles = ["外观","桌宠窗口","输入与权限","快捷键","插件与互动","应用与系统","关于"]
    let pageKeywords = ["主题 深色 浅色 名字 大小 缩放 不透明度 待机 动画 随机 间隔 频率","置顶 全屏 避让 位置 召回 穿透","跨应用 陪打字 输入监控 授权 隐私 键盘","录入 显示 隐藏 热键","菜单 名称 插件 顺序","启动 登录 重置 默认 语言","版本 当前角色 导出"]
    let pageIcons = ["paintpalette","macwindow","hand.raised","keyboard","puzzlepiece.extension","gearshape","info.circle"]
    let search = NSSearchField()
    let heading = NSTextField(labelWithString:"")
    let content = NSView()
    var pages = [NSView]()
    var navigation = [NSButton]()
    var selectedPage = 0
    let languageChoice = NSPopUpButton()
    var languageBindings = [() -> Void]()
    let theme = NSPopUpButton()
    let typingToggle = NSButton(checkboxWithTitle:"跨应用陪打字",target:nil,action:nil)
    let permissionLabel = NSTextField(labelWithString:"")
    let characterLabel = NSTextField(labelWithString:"")
    let idleMinimum = NSPopUpButton()
    let idleMaximum = NSPopUpButton()
    let idleSeconds = [1,3,5,8,12,15,20,30,45,60,90,120]
    let sizeLabel = NSTextField(labelWithString:"")
    let opacityLabel = NSTextField(labelWithString:"")
    let pluginTable = NSTableView()
    let pluginScroll = NSScrollView()
    let menuEditor = NSView()
    let pluginEmpty = NSTextField(labelWithString:"尚未安装插件")
    var changingPlugins = Set<String>()
    let actionChoice = NSPopUpButton()
    let actionShown = NSButton(checkboxWithTitle:"显示在菜单中",target:nil,action:nil)
    let alias = NSTextField()
    let moveUp = NSButton(title:"上移",target:nil,action:nil)
    let moveDown = NSButton(title:"下移",target:nil,action:nil)
    var hasTypingPlugin = false
    lazy var typingInput = TypingInput { [weak self] in
        self?.stage.evaluateJavaScript("stage.feedback?.typingStroke?.()")
    }
    var sleeping=false
    var pluginRows = [[String:Any]]()
    var availableActions = [[String:String]]()
    var actionRows = [[String:String]]()
    var commandGroup:NSMenuItem?
    var insertedItems = [NSMenuItem]()
    var restoreControls: (() -> Void)?
    let name = Bundle.main.object(forInfoDictionaryKey:"CFBundleName") as? String ?? "Jiumi"
    let settings = SettingsPanel(contentRect: NSRect(x:0,y:0,width:740,height:438),
                           styleMask:[.titled,.closable], backing:.buffered, defer:false)
    let defaults: UserDefaults

    init(panel: NSPanel, stage: Stage, identity: String) {
        self.petPanel = panel
        self.stage = stage
        defaults = UserDefaults(suiteName: "studio.jiumi.window." + identity) ?? .standard
        super.init()
        let iconURL = Bundle.main.url(forResource:"Jiumi",withExtension:"icns")
            ?? ProcessInfo.processInfo.environment["JIUMI_CLIENT_ICON"].map { URL(fileURLWithPath:$0) }
        if let url=iconURL, let icon=NSImage(contentsOf:url) {
            NSApp.applicationIconImage=icon
            let small=icon.copy() as! NSImage
            small.size=NSSize(width:21,height:21)
            small.accessibilityDescription=name
            item.button?.image=small
        }
        if item.button?.image == nil { item.button?.title = "啾" }
        item.button?.toolTip = name
        for menu in [commands,context] {
            menu.delegate = self
            menu.addItem(withTitle:"显示"+name,action:#selector(togglePet),keyEquivalent:"").target = self
            menu.addItem(withTitle:"桌宠设置…",action:#selector(showSettings),keyEquivalent:"").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle:"退出"+name,action:#selector(NSApplication.terminate(_:)),keyEquivalent:"").target = NSApp
        }
        item.menu = commands
        stage.petMenu = context
        settings.title = name + " 设置"
        settings.isReleasedWhenClosed = false
        configureNavigation()
        func place(_ view:NSView,_ page:Int,_ x:Int,_ y:Int,_ w:Int,_ h:Int) {
            view.frame = NSRect(x:x,y:y,width:w,height:h)
            pages[page].addSubview(view)
        }
        func label(_ text:String,_ page:Int,_ y:Int) {
            place(NSTextField(labelWithString:text),page,0,y,165,22)
        }
        func button(_ text:String,_ action:Selector) -> NSButton {
            NSButton(title:text,target:self,action:action)
        }
        func slider(_ text:String,_ key:String,_ min:Double,_ max:Double,_ y:Int,_ action:Selector,_ valueLabel:NSTextField) -> NSSlider {
            label(text,0,y)
            let control = NSSlider(value:defaults.object(forKey:key) as? Double ?? 1,minValue:min,maxValue:max,target:self,action:action)
            control.isContinuous = true
            control.setAccessibilityLabel(text)
            place(control,0,172,y,214,24)
            valueLabel.alignment = .right
            place(valueLabel,0,395,y,70,22)
            return control
        }
        label("设置窗口主题",0,296)
        theme.addItems(withTitles:["跟随系统","浅色","深色"])
        theme.selectItem(at:min(2,max(0,defaults.integer(forKey:"settingsTheme"))))
        theme.target=self; theme.action = #selector(changeTheme)
        place(theme,0,304,292,161,30)
        changeTheme()
        let size = slider("角色大小","size",0.65,1.75,236,#selector(setSize(_:)),sizeLabel)
        setSize(size)
        let opacity = slider("窗口不透明度","opacity",0.35,1,178,#selector(setOpacity(_:)),opacityLabel)
        setOpacity(opacity)
        let nameToggle = NSButton(checkboxWithTitle:"显示角色名字",target:self,action:#selector(setNameVisible(_:)))
        nameToggle.state = defaults.bool(forKey:"showName") ? .on : .off
        place(nameToggle,0,0,116,230,26)
        label("待机动作间隔",0,59)
        for (control,key,fallback,x) in [(idleMinimum,"idleMinSeconds",8,209),(idleMaximum,"idleMaxSeconds",20,362)] {
            for seconds in idleSeconds { control.addItem(withTitle:String(seconds)+" 秒") }
            let saved = defaults.integer(forKey:key)
            control.selectItem(at:idleSeconds.firstIndex(of:saved) ?? idleSeconds.firstIndex(of:fallback)!)
            control.setAccessibilityLabel(control === idleMinimum ? "最短待机间隔" : "最长待机间隔")
            control.target=self; control.action = #selector(changeIdleInterval(_:))
            place(control,0,x,56,104,30)
        }
        place(NSTextField(labelWithString:"至"),0,330,59,22,22)
        place(NSTextField(labelWithString:"每轮休息时随机选取等待时间。"),0,0,20,450,22)

        let floating = NSButton(checkboxWithTitle:"保持桌宠置顶",target:self,action:#selector(setFloating(_:)))
        floating.state = defaults.object(forKey:"floating") as? Bool == false ? .off : .on
        setFloating(floating)
        place(floating,1,0,294,225,26)
        avoidFullscreen.state = defaults.object(forKey:"avoidFullscreen") as? Bool == false ? .off : .on
        avoidFullscreen.target=self; avoidFullscreen.action = #selector(applyFullscreenPolicy)
        applyFullscreenPolicy()
        place(avoidFullscreen,1,0,242,225,26)
        passThrough.state = defaults.bool(forKey:"passThrough") ? .on : .off
        passThrough.target=self; passThrough.action = #selector(applyPassThrough)
        applyPassThrough()
        place(passThrough,1,0,190,225,26)
        remember.state = defaults.object(forKey:"rememberPosition") as? Bool == false ? .off : .on
        remember.target=self; remember.action = #selector(setRemember)
        place(remember,1,0,138,225,26)
        place(button("移回当前屏幕",#selector(resetPosition)),1,295,133,170,30)
        if remember.state == .on, let point = defaults.string(forKey:"position") {
            petPanel.setFrameOrigin(NSPointFromString(point))
        }
        ensureOnScreen()
        petPanel.delegate = self

        typingToggle.target=self; typingToggle.action = #selector(toggleTyping)
        place(typingToggle,2,0,294,225,26)
        place(NSTextField(wrappingLabelWithString:"开启后，角色会跟随其他应用里的敲击节奏。输入的文字和按键内容不会传给角色。"),2,0,228,462,52)
        label("输入监控权限",2,168)
        permissionLabel.alignment = .right
        place(permissionLabel,2,185,168,280,22)
        place(button("打开系统输入监控设置",#selector(openInputSettings)),2,250,108,215,30)

        label("显示或隐藏桌宠",3,296)
        shortcutField.placeholderString = "未绑定"
        shortcutField.setAccessibilityLabel("显隐快捷键")
        place(shortcutField,3,244,294,221,26)
        for (i,entry) in [("录入",#selector(recordKey)),("应用",#selector(applyKey)),("清除",#selector(clearKey))].enumerated() {
            place(button(entry.0,entry.1),3,243+i*76,242,73,30)
        }
        place(NSTextField(wrappingLabelWithString:"点击录入后按下组合键，或输入如 ⌃⌥K 的组合再点应用。"),3,0,176,460,48)
        configureManager()
        label("界面语言",5,296)
        languageChoice.addItems(withTitles:["简体中文","English"])
        languageChoice.target=self; languageChoice.action = #selector(changeLanguage)
        place(languageChoice,5,304,292,161,30)
        loginItem.target=self; loginItem.action = #selector(changeLoginItem)
        refreshLoginItem()
        place(loginItem,5,0,234,230,26)
        place(button("恢复桌面设置…",#selector(resetSettings)),5,0,170,178,30)
        label("客户端版本",6,296)
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0"
        place(NSTextField(labelWithString:name+" "+version),6,207,296,250,22)
        label("当前角色",6,236)
        place(characterLabel,6,207,236,250,22)
        place(NSButton(title:"导出角色包…",target:stage,action:#selector(Stage.exportPet)),6,0,160,150,30)
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
            self.idleMinimum.selectItem(at:self.idleSeconds.firstIndex(of:8)!)
            self.idleMaximum.selectItem(at:self.idleSeconds.firstIndex(of:20)!)
            self.changeIdleInterval(self.idleMinimum)
            self.setSize(size)
            self.setOpacity(opacity)
            self.setFloating(floating)
            self.setNameVisible(nameToggle)
            self.setRemember()
            self.clearKey()
            self.resetPosition()
            self.feedback.stringValue = tr("已恢复桌宠设置。")
        }
        hotKey.pressed = { [weak self] in self?.togglePet() }
        if let saved = defaults.string(forKey:"shortcut") {
            shortcutField.stringValue = saved
            applyKey()
        }
        let workspaceEvents=NSWorkspace.shared.notificationCenter
        workspaceEvents.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
        workspaceEvents.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
        bindLanguage(settings.contentView!)
        clientLanguage=startupLanguage
        updateLanguage()
        settings.center()
    }
    func bindLanguage(_ view:NSView) {
        func bind(_ key:String?, _ write:@escaping (String)->Void) {
            guard let key=key, englishText[key] != nil else { return }
            languageBindings.append { write(tr(key)) }
        }
        if let popup=view as? NSPopUpButton {
            for item in popup.itemArray { bind(item.title) { item.title=$0 } }
        } else if let button=view as? NSButton {
            bind(button.title) { button.title=$0 }
        } else if let field=view as? NSTextField {
            bind(field.placeholderString) { field.placeholderString=$0 }
            if !field.isEditable { bind(field.stringValue) { field.stringValue=$0 } }
        }
        bind(view.accessibilityLabel()) { view.setAccessibilityLabel($0) }
        for child in view.subviews { bindLanguage(child) }
    }
    @objc func changeLanguage() {
        clientLanguage=languageChoice.indexOfSelectedItem==1 ? "en" : "zh-CN"
        defaults.set(clientLanguage,forKey:"clientLanguage")
        updateLanguage()
        syncPageLanguage()
    }
    func updateLanguage() {
        languageChoice.selectItem(at:clientLanguage=="en" ? 1 : 0)
        for apply in languageBindings { apply() }
        for control in [idleMinimum,idleMaximum] {
            for (index,item) in control.itemArray.enumerated() { item.title=String(idleSeconds[index])+tr(" 秒") }
        }
        settings.title=name+tr(" 设置")
        for menu in [commands,context] {
            menu.items.first { $0.action == #selector(showSettings) }?.title=tr("桌宠设置…")
            menu.items.first { $0.action == #selector(NSApplication.terminate(_:)) }?.title=tr("退出")+name
            menuNeedsUpdate(menu)
        }
        filterSettings()
        refreshLoginItem()
        refreshInputStatus()
    }
    func syncPageLanguage() {
        stage.callAsyncJavaScript("document.documentElement.lang=language; stage.title=ui('轻点抚摸，长按拖动'); stage.feedback.menuItems=petMenuItems(pet)",
                                  arguments:["language":clientLanguage],in:nil,in:.page) { _ in self.loadPluginMenu() }
    }
    func configureNavigation() {
        guard let root = settings.contentView else { return }
        let sidebar = NSVisualEffectView(frame:NSRect(x:0,y:0,width:192,height:438))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        root.addSubview(sidebar)
        search.frame = NSRect(x:14,y:393,width:164,height:26)
        search.placeholderString = "搜索设置"
        search.target = self; search.action = #selector(filterSettings)
        search.sendsSearchStringImmediately = true
        sidebar.addSubview(search)
        heading.frame = NSRect(x:220,y:378,width:480,height:35)
        heading.font = .systemFont(ofSize:24,weight:.semibold)
        root.addSubview(heading)
        content.frame = NSRect(x:222,y:42,width:485,height:325)
        root.addSubview(content)
        feedback.frame = NSRect(x:222,y:6,width:480,height:34)
        feedback.textColor = .secondaryLabelColor
        root.addSubview(feedback)
        for (index,title) in pageTitles.enumerated() {
            let view = NSView(frame:content.bounds)
            pages.append(view); content.addSubview(view)
            let button = NSButton(title:title,target:self,action:#selector(selectSettingsPage(_:)))
            button.tag = index
            button.image = NSImage(systemSymbolName:pageIcons[index],accessibilityDescription:nil)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.alignment = .left
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            navigation.append(button); sidebar.addSubview(button)
        }
        filterSettings()
    }
    @objc func selectSettingsPage(_ sender:NSButton) {
        selectedPage = sender.tag
        renderPage()
    }
    @objc func filterSettings() {
        let query = search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        var matches = [Int]()
        for (i,button) in navigation.enumerated() {
            button.isHidden = !query.isEmpty && !(pageTitles[i]+" "+tr(pageTitles[i])+" "+pageKeywords[i]+" "+tr(pageKeywords[i])).localizedCaseInsensitiveContains(query)
            if !button.isHidden {
                button.frame = NSRect(x:12,y:348-matches.count*39,width:168,height:34)
                matches.append(i)
            }
        }
        if !matches.contains(selectedPage) { selectedPage = matches.first ?? -1 }
        renderPage()
    }
    func renderPage() {
        settings.record = nil
        feedback.stringValue = ""
        for (i,page) in pages.enumerated() {
            page.isHidden = i != selectedPage
            navigation[i].state = i == selectedPage ? .on : .off
        }
        heading.stringValue = selectedPage < 0 ? tr("没有匹配的设置") : tr(pageTitles[selectedPage])
        if selectedPage == 2 { refreshInputStatus() }
        if selectedPage == 5 { refreshLoginItem() }
    }
    @objc func changeTheme() {
        let selection = theme.indexOfSelectedItem
        defaults.set(selection,forKey:"settingsTheme")
        settings.appearance = selection == 1 ? NSAppearance(named:.aqua) : selection == 2 ? NSAppearance(named:.darkAqua) : nil
    }
    func refreshInputStatus() {
        permissionLabel.stringValue = CGPreflightListenEventAccess() ? tr("已允许") : tr("未授权")
        typingToggle.isEnabled = hasTypingPlugin
        typingToggle.state = hasTypingPlugin && defaults.bool(forKey:"typingInput") ? .on : .off
        typingToggle.toolTip = hasTypingPlugin ? nil : tr("请先启用支持陪打字的角色插件")
    }
    @objc func openInputSettings() {
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    func applicationDidBecomeActive(_ notification:Notification) { refreshInputStatus(); refreshLoginItem() }
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
        loginItem.toolTip = loginItem.isEnabled ? nil : tr("需要 macOS 13 或更高版本的独立应用。")
    }
    @objc func changeLoginItem() {
        guard #available(macOS 13.0,*), bundled != nil else { return }
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .requiresApproval:
                let alert=NSAlert()
                alert.messageText=tr("此登录项等待系统批准")
                alert.addButton(withTitle:tr("打开系统设置"))
                alert.addButton(withTitle:tr("取消登录项"))
                alert.addButton(withTitle:tr("返回"))
                switch alert.runModal() {
                case .alertFirstButtonReturn: SMAppService.openSystemSettingsLoginItems()
                case .alertSecondButtonReturn: try service.unregister()
                default: break
                }
            case .enabled: try service.unregister()
            default: try service.register()
            }
            feedback.stringValue = service.status == .requiresApproval ? tr("请在系统设置的登录项中允许此应用。") : ""
        } catch {
            feedback.stringValue = tr("登录项设置失败：") + error.localizedDescription
        }
        refreshLoginItem()
    }
    func configureManager() {

        let page=pages[4]
        let title=NSTextField(labelWithString:tr("已安装插件"))
        title.font = .systemFont(ofSize:13,weight:.semibold)
        title.frame=NSRect(x:0,y:300,width:460,height:20)
        page.addSubview(title)
        pluginTable.headerView=nil
        pluginTable.rowHeight=42
        pluginTable.style = .inset
        pluginTable.target=self
        pluginTable.doubleAction = #selector(openClickedPlugin)
        pluginTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        pluginTable.allowsColumnReordering=false
        pluginTable.allowsColumnResizing=false
        pluginTable.setAccessibilityLabel(tr("已安装插件"))
        for (id,width) in [("name",252),("version",58),("enabled",108)] {
            let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id))
            column.title=["name":tr("插件"),"version":tr("版本"),"enabled":tr("启用")][id]!
            column.width=CGFloat(width)
            column.resizingMask=id=="name" ? .autoresizingMask : []
            pluginTable.addTableColumn(column)
        }
        pluginTable.dataSource=self; pluginTable.delegate=self
        pluginScroll.borderType = .bezelBorder
        pluginScroll.hasVerticalScroller=true
        pluginScroll.autohidesScrollers=true
        pluginScroll.documentView=pluginTable
        page.addSubview(pluginScroll)
        pluginEmpty.frame=NSRect(x:12,y:257,width:320,height:22)
        pluginEmpty.textColor = .secondaryLabelColor
        page.addSubview(pluginEmpty)
        menuEditor.frame=NSRect(x:0,y:0,width:465,height:145)
        page.addSubview(menuEditor)
        func place(_ v:NSView,_ x:Int,_ y:Int,_ w:Int,_ h:Int) {
            v.frame=NSRect(x:x,y:y-7,width:w,height:h)
            menuEditor.addSubview(v)
        }
        actionChoice.target=self; actionChoice.action = #selector(selectAction)
        actionShown.target=self; actionShown.action = #selector(changeAction)
        alias.setAccessibilityLabel(tr("菜单名称"))
        alias.placeholderString = tr("使用原名称")
        alias.target=self; alias.action = #selector(changeAction)
        moveUp.target=self; moveUp.action = #selector(moveAction(_:))
        moveDown.target=self; moveDown.action = #selector(moveAction(_:))
        place(NSTextField(labelWithString:tr("已启用插件的互动菜单")),0,130,320,22)
        place(actionChoice,0,94,236,30); place(actionShown,250,94,176,30)
        place(NSTextField(labelWithString:tr("菜单名称")),0,59,70,22)
        place(alias,78,58,158,24)
        let save=NSButton(title:tr("应用名称"),target:self,action:#selector(changeAction))
        place(save,248,55,104,30)
        place(moveUp,0,12,76,32); place(moveDown,84,12,76,32)
        place(NSButton(title:tr("恢复默认菜单"),target:self,action:#selector(resetMenu)),248,12,138,32)

    }
    @objc func resetMenu() {
        for key in ["actionLabels","hiddenActions","actionOrder"] { defaults.removeObject(forKey:key) }
        renderMenus()
    }
    func loadPluginMenu() {
        let script = """
        ({character:pet.name, plugins:[...(pet.modules || []),...rules].map(m=>({
            id:m.id,name:m.name,version:m.version,enabled:pet.plugins.includes(m.id),
            kind:m.kind ?? (m.wasm ? 'wasm' : 'rule'),
            summary:typeof m.description==='string' ? m.description.slice(0,320) : '',
            triggers:Object.keys(m.enter ?? {}).concat(m.events ?? [],m.on || [],m.show || []).filter(Boolean).slice(0,5).join('、'),
            speech:m.kind==='speech' && document.documentElement.lang==='en' ? (m.lines.length+' lines, every '+m.minSeconds+'–'+m.maxSeconds+' seconds, displayed for '+m.durationSeconds+' seconds.') : m.kind==='speech' ? (m.lines.length+' 句台词，每隔 '+m.minSeconds+'–'+m.maxSeconds+' 秒随机显示一条，停留 '+m.durationSeconds+' 秒。') : '',
            typing:m.kind==='state-machine' && Object.hasOwn(m.enter,'typing.stroke')
          })),
          typing:pet.modules?.some(m=>m.kind==='state-machine' && pet.plugins.includes(m.id) && Object.hasOwn(m.enter,'typing.stroke')) ?? false,
          actions:stage.feedback.menuItems})
        """
        stage.evaluateJavaScript(script) { result,_ in
            guard let data=result as? [String:Any], let plugins=data["plugins"] as? [[String:Any]],
                  let actions=data["actions"] as? [[String:String]] else { return }
            self.characterLabel.stringValue = data["character"] as? String ?? ""
            self.hasTypingPlugin = data["typing"] as? Bool ?? false
            self.syncTyping()
            self.pluginRows=plugins
            self.availableActions=actions
            self.renderMenus()
        }
    }
    func renderMenus() {
        let order=defaults.stringArray(forKey:"actionOrder") ?? []
        let hidden=defaults.stringArray(forKey:"hiddenActions") ?? []
        let labels=defaults.dictionary(forKey:"actionLabels") as? [String:String] ?? [:]
        let previousAction=actionChoice.selectedItem?.representedObject as? String
        let ordered=order.compactMap { id in availableActions.first { $0["event"]==id } }
            + availableActions.filter { !order.contains($0["event"] ?? "") }
        actionRows=ordered
        menuEditor.isHidden=ordered.isEmpty
        pluginEmpty.isHidden = !pluginRows.isEmpty
        pluginScroll.isHidden=pluginRows.isEmpty
        let bottom:CGFloat=ordered.isEmpty ? 12 : 152
        let listHeight=min(294-bottom,CGFloat(pluginRows.count)*(pluginTable.rowHeight+pluginTable.intercellSpacing.height)+16)
        pluginScroll.frame=NSRect(x:0,y:294-listHeight,width:459,height:listHeight)
        pluginTable.reloadData()
        for item in insertedItems { context.removeItem(item) }
        insertedItems.removeAll()
        if let group=commandGroup { commands.removeItem(group); commandGroup=nil }
        interactions.removeAllItems()
        actionChoice.removeAllItems()
        for action in ordered {
            guard let id=action["event"],let title=action["label"] else { continue }
            let label=labels[id] ?? tr(title)
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
            let group=NSMenuItem(title:tr("互动"),action:nil,keyEquivalent:"")
            group.submenu=interactions
            commands.insertItem(group,at:1)
            commandGroup=group
        }
        if ordered.isEmpty { actionChoice.addItem(withTitle:tr("暂无互动菜单项")) }
        selectAction()
    }
    func numberOfRows(in tableView:NSTableView) -> Int { pluginRows.count }
    @objc func openClickedPlugin() {
        let row=pluginTable.clickedRow
        guard pluginRows.indices.contains(row) else { return }
        showPluginDetails(pluginRows[row])
    }
    @objc func openPluginInfo(_ sender:NSButton) {
        guard let id=sender.identifier?.rawValue, let plugin=pluginRows.first(where:{ $0["id"] as? String == id }) else { return }
        showPluginDetails(plugin)
    }
    func showPluginDetails(_ plugin:[String:Any]) {
        guard settings.attachedSheet == nil else { return }
        let sheet=NSAlert()
        sheet.messageText=tr(plugin["name"] as? String ?? "插件信息")
        let kind=plugin["kind"] as? String ?? ""
        let type=["speech":tr("气泡台词"),"state-machine":tr("互动动作"),"session-notice":tr("会话提醒"),"wasm":tr("本地模块"),"rule":tr("事件规则")][kind] ?? tr("插件")
        var summary=plugin["summary"] as? String ?? ""
        if summary.isEmpty {
            if kind=="speech" { summary=plugin["speech"] as? String ?? "" }
            else if plugin["typing"] as? Bool == true { summary=tr("敲键时，角色会跟随输入节奏做出动作。") }
        }
        let status=plugin["enabled"] as? Bool == true ? tr("已启用") : tr("已关闭")
        var lines=[tr("类型　")+type,tr("版本　v")+String(plugin["version"] as? Int ?? 1),tr("状态　")+status]
        if let triggers=plugin["triggers"] as? String, !triggers.isEmpty { lines.append(tr("触发事件　")+triggers) }
        if let id=plugin["id"] as? String { lines.append(tr("插件标识　")+id) }
        sheet.informativeText=(summary.isEmpty ? "" : summary+"\n\n")+lines.joined(separator:"\n")
        sheet.addButton(withTitle:tr("完成"))
        sheet.beginSheetModal(for:settings)
    }
    func tableView(_ tableView:NSTableView, viewFor tableColumn:NSTableColumn?, row:Int) -> NSView? {
        let plugin=pluginRows[row]
        guard let id=plugin["id"] as? String, let rawTitle=plugin["name"] as? String else { return nil }
        let title=tr(rawTitle)
        if tableColumn?.identifier.rawValue == "enabled" {
            let toggle=NSSwitch()
            toggle.identifier=NSUserInterfaceItemIdentifier(id)
            toggle.setAccessibilityLabel(tr("启用")+title)
            toggle.controlSize = .small
            toggle.state=plugin["enabled"] as? Bool == true ? .on : .off
            toggle.isEnabled = !changingPlugins.contains(id)
            toggle.target=self; toggle.action = #selector(changePlugin(_:))
            let info=NSButton(image:NSImage(systemSymbolName:"info.circle",accessibilityDescription:tr("插件信息"))!,target:self,action:#selector(openPluginInfo(_:)))
            info.identifier=NSUserInterfaceItemIdentifier(id)
            info.isBordered=false
            info.contentTintColor = .secondaryLabelColor
            info.toolTip=tr("查看")+title+tr("的信息")
            info.setAccessibilityLabel(info.toolTip)
            let cell=NSTableCellView()
            for control in [toggle as NSView,info as NSView] {
                control.translatesAutoresizingMaskIntoConstraints=false
                cell.addSubview(control)
                control.centerYAnchor.constraint(equalTo:cell.centerYAnchor).isActive=true
            }
            NSLayoutConstraint.activate([
                info.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-14),
                info.widthAnchor.constraint(equalToConstant:20),
                info.heightAnchor.constraint(equalToConstant:22),
                toggle.trailingAnchor.constraint(equalTo:info.leadingAnchor,constant:-12)
            ])
            return cell
        }
        let isVersion = tableColumn?.identifier.rawValue == "version"
        let label = NSTextField(labelWithString:isVersion ? "v"+String(plugin["version"] as? Int ?? 1) : title)
        label.lineBreakMode = .byTruncatingTail
        if isVersion { label.textColor = .secondaryLabelColor }
        let cell = NSTableCellView()
        label.translatesAutoresizingMaskIntoConstraints=false
        cell.addSubview(label)
        cell.textField=label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo:cell.leadingAnchor),
            label.trailingAnchor.constraint(equalTo:cell.trailingAnchor),
            label.centerYAnchor.constraint(equalTo:cell.centerYAnchor)
        ])
        return cell
    }
    @objc func changePlugin(_ sender:NSSwitch) {
        guard let id=sender.identifier?.rawValue, changingPlugins.insert(id).inserted else { return }
        let enabled=sender.state == .on
        sender.isEnabled=false
        stage.callAsyncJavaScript("return stage.feedback.setPlugin(id,enabled)",arguments:["id":id,"enabled":enabled],in:nil,in:.page) { result in
            if case .success(let response)=result, response as? Bool == true {
                var overrides=self.defaults.dictionary(forKey:"pluginOverrides") ?? [:]
                overrides[id]=enabled
                self.defaults.set(overrides,forKey:"pluginOverrides")
            }
            self.changingPlugins.remove(id)
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
        opacityLabel.stringValue = String(Int((sender.doubleValue*100).rounded()))+"%"
        petPanel.alphaValue = CGFloat(sender.doubleValue)
        defaults.set(sender.doubleValue,forKey:"opacity")
    }
    @objc func resetSettings() {
        let alert = NSAlert()
        alert.messageText = tr("恢复")+name+tr("的桌面设置？")
        alert.informativeText = tr("尺寸、位置、外观和显隐快捷键将恢复默认。")
        alert.addButton(withTitle:tr("取消"))
        alert.addButton(withTitle:tr("恢复默认"))
        alert.beginSheetModal(for:settings) { response in
            if response == .alertSecondButtonReturn { self.restoreControls?() }
        }
    }
    @objc func recordKey() {
        feedback.stringValue = tr("按组合键录入，Esc 取消。")
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
                self.feedback.stringValue = tr("请用 ⌃、⌥ 或 ⌘ 搭配字母或数字，可加 ⇧。")
            }
        }
    }
    @objc func applyKey() {
        settings.record = nil
        guard let key = PetShortcut(shortcutField.stringValue) else {
            feedback.stringValue = tr("请输入有效的组合键。"); return
        }
        if hotKey.replace(with:key) {
            defaults.set(key.label,forKey:"shortcut")
            shortcutField.stringValue = key.label
            feedback.stringValue = tr("已绑定 ") + key.label
        } else {
            feedback.stringValue = tr("组合键已占用或不可用。") + (hotKey.active.map {tr("当前仍使用 ") + $0.label} ?? tr("可通过菜单栏召回。"))
        }
    }
    @objc func clearKey() {
        settings.record = nil
        _ = hotKey.replace(with:nil)
        defaults.removeObject(forKey:"shortcut")
        shortcutField.stringValue = ""
        feedback.stringValue = tr("已清除快捷键。")
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
    @objc func changeIdleInterval(_ sender:NSPopUpButton) {
        if idleMinimum.indexOfSelectedItem > idleMaximum.indexOfSelectedItem {
            let other = sender === idleMinimum ? idleMaximum : idleMinimum
            other.selectItem(at:sender.indexOfSelectedItem)
        }
        defaults.set(idleSeconds[idleMinimum.indexOfSelectedItem],forKey:"idleMinSeconds")
        defaults.set(idleSeconds[idleMaximum.indexOfSelectedItem],forKey:"idleMaxSeconds")
        applyIdleInterval()
    }
    func applyIdleInterval() {
        stage.callAsyncJavaScript("stage.feedback.setIdleInterval(min,max)",
                                  arguments:["min":idleSeconds[idleMinimum.indexOfSelectedItem],"max":idleSeconds[idleMaximum.indexOfSelectedItem]],
                                  in:nil,in:.page,completionHandler:nil)
    }
    @objc func setSize(_ sender:NSSlider) {
        sizeLabel.stringValue = String(Int((sender.doubleValue*100).rounded()))+"%"
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
        defaults.set(enabled,forKey:"passThrough")
    }
    @objc func applyFullscreenPolicy() {
        let enabled = avoidFullscreen.state == .on
        petPanel.collectionBehavior = [.canJoinAllSpaces, enabled ? .fullScreenNone : .fullScreenAuxiliary]
        defaults.set(enabled,forKey:"avoidFullscreen")
    }
    func syncTyping() {
        let enabled = defaults.bool(forKey:"typingInput")
        if hasTypingPlugin && enabled && petPanel.isVisible && !sleeping {
            if !typingInput.start() { defaults.set(false,forKey:"typingInput") }
        } else { typingInput.stop() }
        refreshInputStatus()
    }
    @objc func toggleTyping() {
        defer { refreshInputStatus() }
        if defaults.bool(forKey:"typingInput") {
            defaults.set(false,forKey:"typingInput")
        } else {
            guard CGPreflightListenEventAccess() || CGRequestListenEventAccess() else {
                let alert = NSAlert()
                alert.messageText = tr("允许 ")+name+tr(" 使用输入监控")
                alert.informativeText = tr("在系统设置的「隐私与安全性 → 输入监控」中允许 ")+name+tr("。授权后重新打开客户端，再开启陪打字。角色只接收敲击节奏。")
                alert.addButton(withTitle:tr("打开输入监控"))
                alert.addButton(withTitle:tr("稍后"))
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            guard typingInput.start() else {
                let alert = NSAlert()
                alert.messageText = tr("暂时无法接收敲击，请重开客户端后重试。")
                alert.runModal()
                return
            }
            defaults.set(true,forKey:"typingInput")
        }
        syncTyping()
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        menu.items.first(where: {$0.action == #selector(togglePet)})?.title = (petPanel.isVisible ? tr("隐藏") : tr("显示")) + name
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
        syncTyping()
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
events.onReady = {
    controls.applyIdleInterval()
    controls.applyNameVisibility()
    controls.syncPageLanguage()
    if CommandLine.arguments.contains("--settings") { controls.showSettings() }
}
view.navigationDelegate = events
view.loadFileURL(file,allowingReadAccessTo:file.deletingLastPathComponent())
panel.orderFrontRegardless()
app.run()
