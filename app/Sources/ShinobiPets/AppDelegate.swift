import AppKit
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private(set) var pets: [Pet] = []
    weak var activePet: Pet?
    private var timer: Timer?
    private var last = CACurrentMediaTime()

    func applicationDidFinishLaunching(_ note: Notification) {
        App.delegate = self
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Shinobi Pets") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "🍃"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Desktop.shared.refresh()
        let start = App.config.pets.filter { Assets.byId[$0] != nil }
        for id in start.isEmpty ? ["naruto"] : start { summon(id, save: false) }

        HotKey.register { [weak self] in self?.openCommandBar(for: nil) }

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // `ShinobiPets --mission "play lofi"` runs a mission at launch (handy from Terminal or Shortcuts).
        if let i = CommandLine.arguments.firstIndex(of: "--mission"), i + 1 < CommandLine.arguments.count {
            let text = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let p = self?.anyPet() { Agent.shared.handle(text, pet: p) }
            }
            return
        }

        let greeter = pets.first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            greeter?.say(App.config.apiKey.isEmpty
                ? "Hi! Click me to give me a mission. Add an API key in Settings (🍃 menu) to unlock full AI."
                : "Hi! Click me or press ⌃⌥Space to give me a mission.", seconds: 8)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - last)
        last = now
        Desktop.shared.refreshIfNeeded(now)
        let mouse = NSEvent.mouseLocation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for p in pets {
            p.step(dt)
            p.layout()
            p.updateMouse(mouse)
        }
        CATransaction.commit()
    }

    // MARK: pets

    func pet(_ id: String) -> Pet? { pets.first { $0.meta.id == id } }
    func anyPet() -> Pet? { activePet ?? pets.first }

    func summon(_ id: String, save: Bool = true) {
        guard let m = Assets.byId[id], pet(id) == nil else { return }
        pets.append(Pet(meta: m))
        if save { savePets() }
    }

    func dismiss(_ id: String) {
        guard let i = pets.firstIndex(where: { $0.meta.id == id }) else { return }
        pets[i].remove()
        pets.remove(at: i)
        savePets()
    }

    private func savePets() {
        App.config.pets = pets.map(\.meta.id)
        App.config.save()
    }

    func openCommandBar(for pet: Pet?) {
        if pets.isEmpty { summon("naruto") }
        guard let target = pet ?? anyPet() else { return }
        activePet = target
        CommandBar.shared.show(for: target)
    }

    // MARK: menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(ClosureItem("Give a Mission…   ⌃⌥Space") { [weak self] in self?.openCommandBar(for: nil) })
        let mode = NSMenuItem(title: App.config.apiKey.isEmpty ? "AI: offline (add a key in Settings)" : "AI: Claude (\(App.config.model))",
                              action: nil, keyEquivalent: "")
        mode.isEnabled = false
        menu.addItem(mode)
        menu.addItem(.separator())

        let chars = NSMenu()
        for m in Assets.pets {
            let item = ClosureItem(m.displayName) { [weak self] in
                guard let self else { return }
                if self.pet(m.id) != nil { self.dismiss(m.id) } else { self.summon(m.id) }
            }
            item.state = pet(m.id) != nil ? .on : .off
            chars.addItem(item)
        }
        let charsItem = NSMenuItem(title: "Ninja", action: nil, keyEquivalent: "")
        charsItem.submenu = chars
        menu.addItem(charsItem)
        menu.addItem(ClosureItem("Summon All") { [weak self] in Assets.pets.forEach { self?.summon($0.id) } })
        menu.addItem(ClosureItem("Dismiss All") { [weak self] in
            guard let self else { return }
            self.pets.map(\.meta.id).forEach(self.dismiss)
        })

        let sizes = NSMenu()
        for (name, s) in [("Small", 0.5), ("Medium", 0.75), ("Large", 1.0)] {
            let item = ClosureItem(name) { App.config.scale = s; App.config.save() }
            item.state = abs(App.config.scale - s) < 0.01 ? .on : .off
            sizes.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)

        menu.addItem(.separator())
        menu.addItem(ClosureItem("Settings…", key: ",") { SettingsWindow.shared.show() })
        menu.addItem(ClosureItem("Quit Shinobi Pets", key: "q") { NSApp.terminate(nil) })
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
