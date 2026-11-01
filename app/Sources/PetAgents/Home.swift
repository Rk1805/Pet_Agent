import AppKit
import SwiftUI
import ServiceManagement
#if canImport(Translation)
import Translation
#endif

// MARK: - model

struct MissionEntry: Identifiable {
    let id = UUID()
    let text: String
    let reply: String
    let ok: Bool
    let pet: String
    let date = Date()
}

enum HomeTab: String, CaseIterable {
    case pets = "Pets", missions = "Missions", settings = "Settings", about = "About"
    var icon: String {
        switch self {
        case .pets: return "pawprint.fill"
        case .missions: return "bubble.left.and.text.bubble.right.fill"
        case .settings: return "gearshape.fill"
        case .about: return "info.circle"
        }
    }
}

final class HomeModel: ObservableObject {
    static let shared = HomeModel()
    @Published var selected: [String] = []
    @Published var hidden = false
    @Published var scale = App.config.scale
    @Published var log: [MissionEntry] = []
    @Published var tab: HomeTab = .pets
    @Published var hindi: Hindi.PackStatus = .checking
    @Published var spotifyId = App.config.spotifyClientId
    @Published var spotifySecret = App.config.spotifyClientSecret

    func sync() {
        selected = App.delegate.pets.map(\.meta.id)
        hidden = App.delegate.petsHidden
        scale = App.config.scale
    }

    func record(_ text: String, reply: String, ok: Bool, pet: String) {
        log.insert(MissionEntry(text: text, reply: reply, ok: ok, pet: pet), at: 0)
        if log.count > 50 { log.removeLast() }
    }

    @MainActor func refreshHindi() async { hindi = await Hindi.packStatus() }
}

// MARK: - window

final class HomeWindow: NSObject, NSWindowDelegate {
    static let shared = HomeWindow()
    private var window: NSWindow?

    func show(tab: HomeTab? = nil) {
        if let tab { HomeModel.shared.tab = tab }
        HomeModel.shared.sync()
        NSApp.setActivationPolicy(.regular)        // show in the Dock and ⌘-Tab while Home is open
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Pet Agents"
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.minSize = NSSize(width: 780, height: 560)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: HomeView().environmentObject(HomeModel.shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func snapshot(to dir: URL) {
        HomeModel.shared.sync()
        HomeModel.shared.record("arijit singh ka gaana chalao", reply: "Now playing Kesariya by Arijit Singh on Spotify.", ok: true, pet: "Naruto")
        HomeModel.shared.record("remind me in 20 minutes to stretch", reply: "Timer set for 20 min.", ok: true, pet: "Kakashi")
        for tab in HomeTab.allCases {
            HomeModel.shared.tab = tab
            let view = NSHostingView(rootView: HomeView().environmentObject(HomeModel.shared))
            view.frame = NSRect(x: 0, y: 0, width: 1000, height: 720)
            let w = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("home_\(tab.rawValue).png"))
        }
    }

    /// Tear the SwiftUI view down on close so the window costs nothing while hidden.
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - palette

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
    static let homeAccent = Color(hex: 0xff4a6e)
}

private struct NightBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x05062a), location: 0),
                .init(color: Color(hex: 0x0b0f3c), location: 0.42),
                .init(color: Color(hex: 0x22566a), location: 0.72),
                .init(color: Color(hex: 0x4f9aa0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color(hex: 0x8a86ff, alpha: 0.35)).frame(width: 260, height: 140).blur(radius: 50)
                .offset(x: 120, y: -10)
            Ellipse().fill(Color(hex: 0x15333d, alpha: 0.8)).frame(width: 900, height: 260).blur(radius: 60)
                .offset(x: -200, y: 300)
            Ellipse().fill(Color(hex: 0x1c4450, alpha: 0.7)).frame(width: 700, height: 220).blur(radius: 70)
                .offset(x: 320, y: 260)
        }
        .ignoresSafeArea()
    }
}

// MARK: - sprites

/// Frame 0 of each pet's idle animation, for the grid (cheap: one small image per pet).
enum Thumbnails {
    private static var cache: [String: CGImage] = [:]
    static func image(_ m: PetMeta) -> CGImage? {
        if let c = cache[m.id] { return c }
        guard let a = m.animations["front"], let f = SpriteCache.load(m.id, "front", a, limit: 1).first else { return nil }
        cache[m.id] = f
        return f
    }
}

struct SpriteView: View {
    let frames: [CGImage]
    let size: CGFloat
    var body: some View {
        if frames.count > 1 {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                image(frames[Int(ctx.date.timeIntervalSinceReferenceDate * 10) % frames.count])
            }
        } else if let f = frames.first {
            image(f)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
    private func image(_ cg: CGImage) -> some View {
        Image(decorative: cg, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

private func eraLabel(_ era: String) -> String {
    ["classic": "Part I", "shippuden": "Shippuden", "jonin": "Jonin", "sannin": "Sannin", "akatsuki": "Akatsuki",
     "hero": "Hero", "villain": "Villain"][era] ?? era.capitalized
}

// MARK: - root

struct HomeView: View {
    @EnvironmentObject var model: HomeModel

    var body: some View {
        ZStack(alignment: .bottom) {
            NightBackground()
            Group {
                switch model.tab {
                case .pets: PetsTab()
                case .missions: MissionsTab()
                case .settings: SettingsTab()
                case .about: AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            TabBar().padding(.bottom, 18)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 780, minHeight: 560)
    }
}

private struct TabBar: View {
    @EnvironmentObject var model: HomeModel
    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeTab.allCases, id: \.self) { tab in
                let on = model.tab == tab
                Button { model.tab = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 19, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(on ? Color(hex: 0xff6b81) : .white.opacity(0.85))
                    .frame(width: 112, height: 66)
                    .background(on ? Color(hex: 0x6e3340, alpha: 0.55) : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(hex: 0x1d4650, alpha: 0.82), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

private struct Pill: View {
    let text: String
    let colors: [Color]
    var body: some View {
        Text(text).font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing), in: Capsule())
            .shadow(color: colors.last!.opacity(0.45), radius: 10)
    }
}

// MARK: - pets tab

private enum Category: String, CaseIterable {
    case all = "ALL", naruto = "NARUTO", spiderman = "SPIDER-MAN", heroes = "HEROES", villains = "VILLAINS"
    var icon: String {
        switch self {
        case .all: return ""; case .naruto: return "🍥 "; case .spiderman: return "🕷 "
        case .heroes: return "🦸 "; case .villains: return "😈 "
        }
    }
    func includes(_ m: PetMeta) -> Bool {
        switch self {
        case .all: return true
        case .naruto: return m.packID == "naruto"
        case .spiderman: return m.packID == "spiderman"
        case .heroes: return m.era != "villain" && m.era != "akatsuki"
        case .villains: return m.era == "villain" || m.era == "akatsuki"
        }
    }
}

private struct PetsTab: View {
    @EnvironmentObject var model: HomeModel
    @State private var category: Category = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Text("Selected").font(.system(size: 34, weight: .heavy))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 12) {
                            Pill(text: AIAvailability.available ? "🧠 On-device AI" : "⚡️ Simple mode",
                                 colors: [Color(hex: 0xffd23f), Color(hex: 0xffa630)])
                            Button { App.delegate.openCommandBar(for: nil) } label: {
                                Pill(text: "💬 Give a Mission   ⌃⌥Space", colors: [Color(hex: 0x4f7cff), Color(hex: 0xc04dff)])
                            }.buttonStyle(.plain)
                        }
                        Text("Everything runs privately on your Mac ✨").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                if model.selected.isEmpty {
                    Text("No pets on your desktop. Pick one below.").foregroundStyle(.white.opacity(0.6)).frame(height: 150)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(model.selected, id: \.self) { id in
                            if let m = Assets.byId[id] { SelectedCell(meta: m) }
                        }
                    }
                }

                HStack(spacing: 18) {
                    Text("More Pets").font(.system(size: 34, weight: .heavy))
                    Button { category = .spiderman } label: {
                        Pill(text: "🕷  New: Spider-Man pack", colors: [Color(hex: 0xff4a4a), Color(hex: 0xd62f6b)])
                    }.buttonStyle(.plain)
                }
                .padding(.top, 30)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Category.allCases, id: \.self) { c in
                            let on = c == category
                            Button { category = c } label: {
                                Text(c.icon + c.rawValue).font(.system(size: 16, weight: .heavy))
                                    .padding(.horizontal, 18).padding(.vertical, 11)
                                    .background(on ? Color.homeAccent : Color(hex: 0x1a2550, alpha: 0.7), in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(on ? 0 : 0.12)))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                let more = Assets.pets.filter { category.includes($0) && !model.selected.contains($0.id) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 22) {
                    ForEach(more, id: \.id) { m in GridCell(meta: m) }
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 32).padding(.top, 44)
        }
    }
}

private struct SelectedCell: View {
    let meta: PetMeta
    @State private var hover = false
    var body: some View {
        Button { App.delegate.dismiss(meta.id) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    SpriteView(frames: SpriteCache.shared.frames(meta.id, "front", meta.animations["front"]!), size: 130)
                    if hover {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, Color.homeAccent)
                    }
                }
                Text(meta.name).font(.system(size: 15, weight: .medium))
                Text(eraLabel(meta.era)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 150)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Click to send \(meta.shortName) away")
        .contextMenu {
            Button("Give a Mission…") { App.delegate.openCommandBar(for: App.delegate.pet(meta.id)) }
            Button("Send Away") { App.delegate.dismiss(meta.id) }
        }
    }
}

private struct GridCell: View {
    let meta: PetMeta
    @State private var walk: [CGImage] = []
    var body: some View {
        Button { App.delegate.summon(meta.id) } label: {
            VStack(spacing: 6) {
                if walk.isEmpty {
                    SpriteView(frames: Thumbnails.image(meta).map { [$0] } ?? [], size: 130)
                } else {
                    SpriteView(frames: walk, size: 130)
                }
                Text(meta.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(eraLabel(meta.era)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(width: 150)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(meta.tagline)
        .onHover { on in   // walk while hovered; frames are dropped again afterwards
            if on, let a = meta.animations["walk"] { walk = SpriteCache.load(meta.id, "walk", a) } else { walk = [] }
        }
    }
}

// MARK: - missions tab

private struct MissionsTab: View {
    @EnvironmentObject var model: HomeModel
    @State private var text = ""
    @State private var petID = ""

    private let examples: [(String, [String])] = [
        ("🎵 Music", ["play Kesariya", "pause", "next song", "what's playing?"]),
        ("🗂 Apps & web", ["open Notes", "quit Safari", "open youtube", "search best ramen in Tokyo"]),
        ("⌨️ Type for me", ["ask claude for a quick pasta recipe", "write a haiku about rain in notes", "type hello in claude"]),
        ("🎮 Games", ["play batman", "launch cs2 on steam"]),
        ("⏰ Timers", ["remind me in 20 minutes to stretch", "timer for 5 min"]),
        ("📅 Reminders & Calendar", ["remind me to call mom tomorrow at 5pm", "what are my reminders today",
                                    "schedule dentist next friday at 3pm", "what's on my calendar tomorrow"]),
        ("💬 WhatsApp", ["open chat with mom on whatsapp", "message mom on whatsapp saying I'll be late", "send it"]),
        ("🖥 Mac", ["volume 30", "turn it down a bit", "dark mode", "battery?"]),
        ("🇮🇳 Hindi", ["arijit singh ka gaana chalao", "whatsapp pe mom ko hi likho", "kal 5 baje yaad dilana ki dawai leni hai",
                      "kal ka schedule kya hai"]),
        ("🕷 Pets", ["summon venom", "do a web swing", "dismiss doc ock"]),
    ]

    private func send(_ s: String) {
        let s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if App.delegate.pets.isEmpty { App.delegate.summon("naruto") }
        guard let pet = App.delegate.pet(petID) ?? App.delegate.anyPet() else { return }
        Agent.shared.handle(s, pet: pet)
        text = ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Missions").font(.system(size: 34, weight: .heavy))
                HStack(spacing: 10) {
                    Picker("", selection: $petID) {
                        Text("Any pet").tag("")
                        ForEach(model.selected, id: \.self) { id in Text(Assets.byId[id]?.shortName ?? id).tag(id) }
                    }
                    .labelsHidden().frame(width: 130)
                    TextField("Type a mission, in English or Hindi…", text: $text)
                        .textFieldStyle(.plain).font(.system(size: 16))
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Color(hex: 0x1a2550, alpha: 0.8), in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit { send(text) }
                    Button { send(text) } label: { Pill(text: "Send", colors: [Color(hex: 0x4f7cff), Color(hex: 0xc04dff)]) }
                        .buttonStyle(.plain)
                }
                Text("Try saying").font(.system(size: 20, weight: .bold)).padding(.top, 8)
                ForEach(examples, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(group.1, id: \.self) { ex in
                                    Button { text = ex } label: {      // fill the box; you press Send
                                        Text(ex).font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Color(hex: 0x1a2550, alpha: 0.7), in: Capsule())
                                            .overlay(Capsule().stroke(.white.opacity(0.12)))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Text("Recent").font(.system(size: 20, weight: .bold)).padding(.top, 8)
                if model.log.isEmpty {
                    Text("Nothing yet. Click a pet on your desktop or press ⌃⌥Space anywhere.")
                        .foregroundStyle(.white.opacity(0.6))
                }
                ForEach(model.log) { e in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: e.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(e.ok ? Color.green : Color.orange).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(e.text).font(.system(size: 14, weight: .semibold))
                            Text("\(e.pet): \(e.reply)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        Text(e.date.formatted(date: .omitted, time: .shortened)).font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(12)
                    .background(Color(hex: 0x0e1640, alpha: 0.6), in: RoundedRectangle(cornerRadius: 12))
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 32).padding(.top, 44)
        }
    }
}

// MARK: - settings tab

private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 17, weight: .bold))
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0e1640, alpha: 0.65), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
    }
}

private struct SettingsTab: View {
    @EnvironmentObject var model: HomeModel
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var downloadHindi = 0
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.system(size: 34, weight: .heavy))
                Card(title: "Pets") {
                    HStack {
                        Text("Size")
                        Spacer()
                        Picker("", selection: Binding(get: { model.scale }, set: { v in
                            model.scale = v; App.config.scale = v; App.config.save()
                        })) {
                            Text("Small").tag(0.5); Text("Medium").tag(0.75); Text("Large").tag(1.0)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                    }
                    Toggle("Show pets on the desktop", isOn: Binding(get: { !model.hidden },
                                                                     set: { App.delegate.setPetsHidden(!$0) }))
                    Toggle("Open Pet Agents when I log in", isOn: Binding(get: { loginItem }, set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = ""
                        } catch { loginError = error.localizedDescription }
                        loginItem = SMAppService.mainApp.status == .enabled
                    }))
                    if !loginError.isEmpty { Text(loginError).font(.system(size: 12)).foregroundStyle(.orange) }
                }
                Card(title: "Understanding") {
                    Text(AIAvailability.available
                         ? "Apple Intelligence (on-device) understands free-form requests. Nothing leaves your Mac."
                         : AIAvailability.hint)
                        .foregroundStyle(.white.opacity(0.8))
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hindi").font(.system(size: 14, weight: .semibold))
                            Text(hindiText).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        if model.hindi == .downloadable {
                            Button("Download Hindi") { downloadHindi += 1 }
                        } else if model.hindi == .installed {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .modifier(HindiDownloader(trigger: downloadHindi))
                }
                Card(title: "Spotify (optional)") {
                    Text("Lets your pet press play on the exact song. Create a free app at developer.spotify.com/dashboard and copy its Client ID and Secret. Without them, songs open in Spotify's search.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    TextField("Client ID", text: $model.spotifyId).textFieldStyle(.roundedBorder)
                    SecureField("Client Secret", text: $model.spotifySecret).textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        if saved { Text("Saved").foregroundStyle(.green) }
                        Button("Save") {
                            App.config.spotifyClientId = model.spotifyId.trimmingCharacters(in: .whitespacesAndNewlines)
                            App.config.spotifyClientSecret = model.spotifySecret.trimmingCharacters(in: .whitespacesAndNewlines)
                            App.config.save()
                            saved = true
                        }
                    }
                }
                Card(title: "Shortcut") {
                    Text("Press ⌃⌥Space anywhere to give a mission, or click a pet on your desktop.")
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 32).padding(.top, 44)
        }
        .task { await model.refreshHindi() }
    }

    private var hindiText: String {
        switch model.hindi {
        case .checking: return "Checking…"
        case .installed: return "Common Hindi and Hinglish commands work, and other Hindi is translated on-device."
        case .downloadable: return "Common Hindi and Hinglish commands already work. Download the on-device Hindi pack to understand everything else."
        case .unsupported: return "Common Hindi and Hinglish commands work. Full Hindi needs macOS 26."
        }
    }
}

/// Asks macOS to download the Hindi ↔ English translation pack (shows the system download prompt).
private struct HindiDownloader: ViewModifier {
    let trigger: Int
    @EnvironmentObject var model: HomeModel

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            content.modifier(Downloader(trigger: trigger, model: model))
        } else { content }
        #else
        content
        #endif
    }

    #if canImport(Translation)
    @available(macOS 15.0, *)
    private struct Downloader: ViewModifier {
        let trigger: Int
        let model: HomeModel
        @State private var config: TranslationSession.Configuration?
        func body(content: Content) -> some View {
            content
                .onChange(of: trigger) { _ in
                    config = .init(source: .init(identifier: "hi"), target: .init(identifier: "en"))
                }
                .translationTask(config) { session in
                    try? await session.prepareTranslation()
                    await model.refreshHindi()
                }
        }
    }
    #endif
}

// MARK: - about tab

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let n = Assets.byId["naruto"], let img = Thumbnails.image(n) {
                    SpriteView(frames: [img], size: 150)
                }
                Text("Pet Agents").font(.system(size: 40, weight: .heavy))
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundStyle(.white.opacity(0.6))
                Text("Little desktop companions that get things done.").font(.system(size: 17, weight: .medium))
                VStack(alignment: .leading, spacing: 10) {
                    Label("Private: commands are understood on your Mac by a built-in parser and Apple Intelligence.", systemImage: "lock.fill")
                    Label("Light: about 25 MB of memory and ~2% CPU while pets roam.", systemImage: "leaf.fill")
                    Label("Speaks English, Hindi and Hinglish.", systemImage: "character.bubble.fill")
                    Label("Characters: the Naruto and Spider-Man packs (fan-made pixel art).", systemImage: "sparkles")
                }
                .font(.system(size: 14))
                .padding(20)
                .background(Color(hex: 0x0e1640, alpha: 0.65), in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 560)
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
        }
    }
}
