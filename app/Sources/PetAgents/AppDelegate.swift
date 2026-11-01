import AppKit
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private(set) var pets: [Pet] = []
    weak var activePet: Pet?
    private var timer: Timer?
    private var fast = true
    private(set) var petsHidden = false
    private var last = CACurrentMediaTime()

    func applicationDidFinishLaunching(_ note: Notification) {
        App.delegate = self
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pet Agents") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "🐾"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Desktop.shared.refresh()
        let start = App.config.pets.filter { Assets.byId[$0] != nil }
        for id in start.isEmpty ? ["naruto"] : start { summon(id, save: false) }

        HotKey.register { [weak self] in self?.openCommandBar(for: nil) }

        startTimer(fast: true)

        // `PetAgents --snapshot <dir>` renders each Home tab to PNG (for checking the design), then quits.
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                HomeWindow.snapshot(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                NSApp.terminate(nil)
            }
            return
        }

        if CommandLine.arguments.contains("--wa-clear") {
            Task { @MainActor in await WhatsApp.clearBox(); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--wa-selftest") {
            Task { @MainActor in await WhatsApp.selfTest(); NSApp.terminate(nil) }
            return
        }

        // `PetAgents --mission "play lofi"` runs a mission at launch (handy from Terminal or Shortcuts).
        if let i = CommandLine.arguments.firstIndex(of: "--mission"), i + 1 < CommandLine.arguments.count {
            let text = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let p = self?.anyPet() { Agent.shared.handle(text, pet: p) }
            }
            return
        }

        if !App.config.welcomed {        // first launch: show Home, like Pets Therapy
            App.config.welcomed = true
            App.config.save()
            HomeWindow.shared.show()
        }

        let greeter = pets.first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            greeter?.say("Hi! Click me or press ⌃⌥Space to give me a mission.", seconds: 8)
        }
    }

    /// 30 fps while something moves, 10 fps (the animation rate) when every pet is standing still.
    private func startTimer(fast: Bool) {
        timer?.invalidate()
        self.fast = fast
        let t = Timer(timeInterval: fast ? 1.0 / 30.0 : 1.0 / 10.0, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = fast ? 0.005 : 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Clicking the app again in Finder / Launchpad / Spotlight opens Home.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        HomeWindow.shared.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func setPetsHidden(_ hidden: Bool) {
        petsHidden = hidden
        pets.forEach { $0.setVisible(!hidden) }
        if hidden { timer?.invalidate(); timer = nil } else if timer == nil { startTimer(fast: true) }
        HomeModel.shared.sync()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.12, now - last)
        last = now
        Desktop.shared.refreshIfNeeded(now, interval: pets.map(\.windowInfoInterval).min() ?? 2)
        let mouse = NSEvent.mouseLocation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in pets {
            p.step(dt)
            p.layout()
            p.updateMouse(mouse)
        }
        CATransaction.commit()
        let wantFast = pets.contains { $0.needsFastUpdates }
        if wantFast != fast { startTimer(fast: wantFast) }
    }

    // MARK: pets

    func pet(_ id: String) -> Pet? { pets.first { $0.meta.id == id } }
    func anyPet() -> Pet? { activePet ?? pets.first }

    func summon(_ id: String, save: Bool = true) {
        guard let m = Assets.byId[id], pet(id) == nil else { return }
        if petsHidden { setPetsHidden(false) }
        pets.append(Pet(meta: m))
        if save { savePets() }
        HomeModel.shared.sync()
    }

    func dismiss(_ id: String) {
        guard let i = pets.firstIndex(where: { $0.meta.id == id }) else { return }
        pets[i].remove()
        pets.remove(at: i)
        savePets()
        HomeModel.shared.sync()
    }

    private func savePets() {
        App.config.pets = pets.map(\.meta.id)
        App.config.save()
    }

    func openCommandBar(for pet: Pet?) {
        if pets.isEmpty { summon("naruto") }
        if petsHidden { setPetsHidden(false) }
        guard let target = pet ?? anyPet() else { return }
        activePet = target
        CommandBar.shared.show(for: target)
    }

    // MARK: menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let home = ClosureItem("Home", key: "h") { HomeWindow.shared.show(tab: .pets) }
        menu.addItem(home)
        menu.addItem(ClosureItem("Give a Mission…") { [weak self] in self?.openCommandBar(for: nil) })
        let hide = ClosureItem("Hide/Show Pets", key: "p") { [weak self] in
            guard let self else { return }
            self.setPetsHidden(!self.petsHidden)
        }
        hide.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(hide)
        menu.addItem(ClosureItem("Settings…", key: ",") { HomeWindow.shared.show(tab: .settings) })
        menu.addItem(.separator())
        let mode = NSMenuItem(title: MainActor.assumeIsolated { Agent.statusText }, action: nil, keyEquivalent: "")
        mode.isEnabled = false
        menu.addItem(mode)
        menu.addItem(ClosureItem("Quit", key: "q") { NSApp.terminate(nil) })
    }

    /// Hidden main menu so ⌘C / ⌘V / ⌘A work in text fields of this menu-bar app.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
