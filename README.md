# Pet Agents

Desktop pets that are also your on-device assistant. Two character packs so far:

- **Naruto pack:** 18 ninja (below).
- **Spider-Man pack:** Spider-Man, Miles Morales, Spider-Gwen, Doctor Octopus, Green Goblin and Venom.

They are full-length pixel-art sprites (about 170px tall) that walk along the bottom of the
screen and on top of your windows, can be picked up and dragged, and now and then pull off
their signature moves.

They also work as your **AI manager**: click a ninja, type a mission ("play Blinding Lights",
"open Notes", "remind me in 20 minutes to stretch") and it gets done on your Mac.

## Setup

You build the app yourself from this folder; it takes a few minutes. You do **not** need
Xcode: Apple's free **Command Line Tools** are enough (about 1.9 GB installed, against 15+ GB
for Xcode). Nothing else is needed: no Python, Homebrew, Node or API keys. The sprites are
already in the repo.

### What you need

| | |
| --- | --- |
| macOS | Built and tested on macOS 26 (Apple Silicon). The code targets macOS 13+, but older versions and Intel Macs haven't been tested yet |
| For the AI | macOS 26 with **Apple Intelligence** switched on (Apple Silicon). Without it, the pets and all the built-in commands still work; only free-form requests need it |
| Disk | about 2 GB for the Command Line Tools, ~30 MB for the app |

### Steps

1. **Install the Command Line Tools** (skip if you already have them or Xcode).
   Open **Terminal** (Spotlight → "Terminal") and run:

   ```sh
   xcode-select --install
   ```

   A window pops up: click **Install** and wait for it to finish (5–15 minutes depending on
   your connection). Check it worked:

   ```sh
   xcode-select -p        # prints /Library/Developer/CommandLineTools (or an Xcode path)
   swift --version        # prints a Swift version
   ```

   If the tools are already installed but older than your macOS, update them in
   **System Settings → General → Software Update** (the AI features need the macOS 26 SDK).

2. **Get the code.** Either clone it:

   ```sh
   git clone <this repo's URL> Pet-Agent
   cd Pet-Agent
   ```

   or download the ZIP from the repo page, unzip it, and `cd` into the folder in Terminal
   (type `cd ` and drag the folder onto the Terminal window).

3. **Create a signing certificate (once per Mac, recommended).**

   ```sh
   app/make-signing-cert.sh
   ```

   This adds a local certificate called "Pet Agents Local Signing" to your login keychain.
   The build signs the app with it, so macOS remembers the app's permissions (Accessibility,
   Automation) every time you rebuild. If you skip it, the app is ad-hoc signed and you have to
   re-grant Accessibility after every rebuild. Undo: Keychain Access → login → My Certificates →
   delete "Pet Agents Local Signing".

4. **Build the app.**

   ```sh
   app/build.sh
   ```

   The first build takes 1–3 minutes. It ends with `Built …/app/build/PetAgents.app`.

5. **Open it** (and optionally keep it in Applications):

   ```sh
   open app/build/PetAgents.app
   cp -R app/build/PetAgents.app /Applications/    # optional
   ```

   A 🐾 icon appears in the menu bar, pets drop onto your desktop, and **Home** opens.
   **Home → Settings → Open Pet Agents when I log in** starts it automatically.

6. **Turn things on** (each is optional; macOS asks the first time it's needed):

   | For | Where |
   | --- | --- |
   | Understanding free-form requests | System Settings → **Apple Intelligence & Siri** → on (it downloads its model once) |
   | Typing into apps (Claude, Notes…) and shortcuts | System Settings → Privacy & Security → **Accessibility** → Pet Agents on |
   | Controlling Spotify, dark mode | Click **OK** on the "Pet Agents wants to control…" prompts (Privacy & Security → **Automation**) |
   | Full Hindi (beyond the built-in Hinglish commands) | Home → Settings → **Download Hindi** |
   | Playing the exact song on Spotify | Free app at developer.spotify.com/dashboard → paste Client ID + Secret in Home → Settings |

7. **Try it:** click a pet (or press **⌃⌥Space** anywhere) and type `open notes`,
   `play blinding lights`, `type hello in claude` or `remind me in 1 minute to stretch`.

### Updating

```sh
git pull
app/build.sh
```

Quit the running app first (🐾 → Quit), then open the new build. With the certificate from
step 3 your permissions carry over.

### Troubleshooting

| Problem | Fix |
| --- | --- |
| `xcrun: error: invalid active developer path` | The Command Line Tools aren't installed: run `xcode-select --install` |
| Build error mentioning `FoundationModels` | Command Line Tools are older than macOS 26: update them in Software Update |
| "I need Accessibility permission" even though it's on | The entry belongs to an older build. In Accessibility, select Pet Agents → **−**, then **+** → `app/build/PetAgents.app` → on. Run step 3 so it doesn't happen again |
| "Simple mode" / AI doesn't understand free-form requests | Apple Intelligence is off, still downloading, or this Mac can't run it (Intel or older macOS). Built-in commands still work |
| Pets don't appear | 🐾 → Hide/Show Pets, or Home → Settings → Show pets |
| Someone sent you a pre-built `PetAgents.app` and macOS says it "can't verify the developer" | Right-click the app → **Open** → **Open** (only needed once). Building it yourself avoids this |

### Uninstall

Quit the app (🐾 → Quit), then delete `PetAgents.app`, the folder
`~/Library/Application Support/PetAgents`, and (if you made it) the "Pet Agents Local Signing"
certificate in Keychain Access. Remove Pet Agents from Privacy & Security → Accessibility /
Automation if it's listed.

## Desktop app (macOS)

A native menu-bar app in `app/` (Swift + AppKit, no dependencies). The pets live in
transparent, always-on-top windows on your **real desktop**: they walk along the top of the
Dock and on top of your actual app windows, ride along when you drag a window, fall off
edges, and let clicks pass through to whatever is underneath them.

See [Setup](#setup) to install it.

| Do this | What happens |
| --- | --- |
| **Click** a pet, or press **⌃⌥Space** anywhere | A command box opens above its head. Type a mission and press Return (↑ recalls earlier ones) |
| **Drag** a pet | Pick it up; let go and it falls onto the window or Dock below |
| **Right-click** a pet | Jutsu, idle animations, dismiss |
| **🐾 menu bar icon** | Home, Give a Mission, Hide/Show Pets, Settings, Quit |
| Open the app again (Finder / Spotlight) | Opens **Home** |

### Home

A Pets Therapy–style window with a tab bar:

- **Pets:** your selected pets (animated; click one to send it away) and the full roster with
   category chips (All / Part I / Shippuden / Legends). Click a pet to put it on your desktop;
   hover to see it walk.
- **Missions:** type a mission, tap an example, and see recent missions with each pet's reply.
- **Settings:** pet size, show/hide pets, open at login, the Hindi language pack, Spotify keys.
- **About.**

### Missions

| Ask for… | Example |
| --- | --- |
| Music (Spotify) | "play Blinding Lights by The Weeknd", "pause", "next song", "what's playing?", "shuffle on" |
| Apps | "open Notes", "launch VS Code", "quit Safari", "open github.com in Safari" |
| Send to AI apps | "type hello in claude", "send what is 2+2 to claude", "tell claude …", "ask chatgpt for a joke", "open a new chat in claude and ask it …". In Claude, ChatGPT, Perplexity, Gemini and Copilot the message is **sent** (Return pressed); add "but don't send" (Hindi: "bina bheje") to only type it |
| Type for you | "type buy milk in notes" (other apps only type; add "and send" to press Return), "write a haiku about rain in notes" (the pet writes it first), "close this tab in safari" |
| Games | "play batman", "launch cs2 on steam": finds installed Steam games (every library) and starts them; not installed opens the Steam store |
| Timers / reminders | "remind me in 25 minutes to take a break", "timer for 10 min" |
| Web | "open github.com", "search best ramen in Tokyo", "youtube lofi beats" |
| Files | "open my downloads" |
| Mac | "volume 30", "mute", "dark mode", "battery?" |
| Apple Shortcuts | "run my Morning shortcut" (anything you have built in Shortcuts) |
| The pets | "do a rasengan", "summon Itachi", "dismiss Sakura" |
| Hindi / Hinglish | "hello kaise ho claude ko bhej do", "claude mein hello likho", "claude se pucho chawal kaise banaye", "steam pe batman khelo", "venom ko bulao", "arijit singh ka gaana chalao", "notes kholo", "10 minute baad yaad dilana paani peena", "awaaz kam karo", "केसरिया बजाओ" |

**How it understands you** (everything stays on your Mac, no API keys, no downloads):

1. A built-in command parser handles the common phrasings above instantly, with no model at all.
2. Anything else ("how much juice is left?", "turn it down a bit", "show me funny cat videos")
   goes to **Apple's on-device model** (Apple Intelligence, macOS 26+), which picks the right
   action with tool calling. The model is part of macOS: the OS loads and unloads it and
   shares it with Siri and Writing Tools, so the pet itself stays at about 25 MB of RAM. It
   remembers the last few minutes, so follow-ups like "louder" work.

On Macs without Apple Intelligence (Intel, older macOS, or switched off) the parser still works;
the pet tells you how to turn on the rest.

**Hindi:** Apple's on-device model doesn't support Hindi, so the pet handles it in two steps.
Common commands in Hinglish or Devanagari (play, pause, next, open, close, volume, reminders,
search, battery, time) are rewritten into English commands by rules, with nothing to download.
Other Devanagari text is translated to English on-device with Apple's Translation framework and
the reply is translated back to Hindi. That needs the Hindi language pack: **Home → Settings →
Download Hindi**. Check how a phrase is understood with
`PetAgents.app/Contents/MacOS/PetAgents --hindi "gaana chalao"`.

**Playing a specific song:** without setup, the pet opens Spotify's search for the song. To
have it press play on the exact track, create a free app at developer.spotify.com/dashboard
and paste its Client ID and Secret into **Home → Settings**.

**Lightweight:** about 25 MB of memory and around 2% CPU. It redraws at 30 fps only while a
pet moves and at 10 fps when they all stand still, and only re-reads window positions often
while a pet is falling or standing on a window.

**Permissions:** the first time the pet controls Spotify or System Events, macOS asks you to
allow it (System Settings → Privacy & Security → Automation). Typing into apps and keyboard
shortcuts need **Accessibility** (Privacy & Security → Accessibility → Pet Agents); the pet opens
that page the first time. With the local signing certificate (Setup, step 3) permissions survive
rebuilds; without it you have to re-grant them after each build.

Settings are stored in `~/Library/Application Support/PetAgents/config.json` (mode 600).
For testing, `PetAgents.app/Contents/MacOS/PetAgents --mission "play lofi"` runs a mission
at launch and prints the result (add `PETAGENTS_DRYRUN=1` to log the actions instead of doing them), and `--snapshot <folder>` renders each Home tab to PNG.

| File in `app/Sources/PetAgents/` | What it does |
| --- | --- |
| `Desktop.swift` | Reads real window frames (CGWindowList) and screen floors as platforms |
| `Pet.swift` | Per-pet window, physics, animation, dragging, speech bubble |
| `Agent.swift` | Mission flow and the offline command parser |
| `OnDeviceAI.swift` | Apple's on-device model (FoundationModels) with the pet's tools |
| `Tools.swift` | The tool definitions the agent can call, plus timers |
| `MacActions.swift` | Apps, Spotify (AppleScript + Web API), volume, Shortcuts, etc. |
| `Hindi.swift` | Hindi / Hinglish command rules and on-device translation |
| `Home.swift` | The Home window (SwiftUI): Pets, Missions, Settings, About |
| `AppIcon.swift` | Draws the app icon from the sprites (used by `build.sh`) |
| `UI.swift` | Command box, global hotkey |
| `AppDelegate.swift` | Menu bar item, pet roster, the 30 / 10 fps loop |

## What's here

| Path | What it is |
| --- | --- |
| `PetsAssets/` | Every frame as a PNG, using Pet Therapy's naming: `{id}_{animation}-{n}.png` |
| `Species/` | One Pet Therapy–style species JSON per character (animations, loops, `size`, `isMoving`, speed) |
| `app/` | The native macOS desktop app (see above) |
| `preview/index.html` | Browser preview: a fake desktop with walking pets, plus a gallery of every animation |
| `preview/strips/`, `preview/manifest.js` | One sprite strip per animation and the metadata the preview reads |
| `art/` | The character sheet plus one cut-out per character. These are the design reference the sprites copy (outfits, colours). |
| `tools/sprites/` | The Python generator that draws and animates every sprite and jutsu effect |
| `docs/roster.png` | Line-up of the whole cast |

## Browser preview

The original browser preview is still there for checking sprites:

```sh
open preview/index.html          # starts with 4 pets
open "preview/index.html?all"    # summons everyone
```

- **Click** a pet to make it do a random jutsu
- **Right-click** a pet for a menu with all its animations
- **Drag** a pet to pick it up; let go and it falls onto the window or dock below
- **Drag the windows** around: pets walk on top of them and fall off the edges
- The **Gallery** tab plays any animation of any character on demand

## The Spider-Man pack

| Character | Side | Moves | Idle |
| --- | --- | --- | --- |
| Spider-Man | Hero | Web Swing (travels across the screen), Web Shooter | Pizza slice |
| Miles Morales | Hero | Web Swing, Venom Strike, Camouflage | Headphones on |
| Spider-Gwen | Hero | Web Swing, Web Shooter | Drum practice |
| Doctor Octopus | Villain | Tentacle Slam, Rise of the Arms (lifted on two tentacles) | Tea break |
| Green Goblin | Villain | Pumpkin Bomb, Goblin Glider (flies across the screen) | Evil cackle |
| Venom | Villain | Symbiote Lash, "We Are Venom!" | Chocolate |

Defined in `tools/sprites/spider.py` (designs, effects and moves). Masked faces (lenses, web
lines, Venom's jaws) and suit webbing on arms and legs are rig features in `body.py`
(`Character(mask=…)`, outfit `arm_web` / `leg_web`), so more masked heroes are easy to add.

## The Naruto cast

Base animations for everyone: `front` (idle), `walk`, `drag`, `sleep`, plus one
personal idle (snack / hobby).

| Character | Era | Jutsu | Idle |
| --- | --- | --- | --- |
| Naruto | Part I | Shadow Clone, Rasengan | Ichiraku Ramen |
| Naruto | Shippuden | Rasenshuriken, Sage Mode, Shadow Clone | Ichiraku Ramen |
| Sasuke | Part I | Chidori, Great Fireball | Tomato |
| Sasuke | Shippuden | Chidori, Amaterasu, Susanoo (purple) | Tomato |
| Sakura | Part I | Inner Sakura "CHA!", Substitution (log) | Dango |
| Sakura | Shippuden | Cherry Blossom Impact, Mystic Palm | Dango |
| Shikamaru | Part I | Shadow Possession, Shadow Neck Bind, Cloud Watching | Shogi |
| Shikamaru | Shippuden | Shadow Possession, Shadow Stitching | Shogi |
| Ino | Part I | Mind Transfer, Flower Storm | Flower |
| Ino | Shippuden | Mind Transfer, Mystic Palm | Flower |
| Choji | Part I | Expansion, Human Bullet Tank (rolls across the screen) | Chips |
| Choji | Shippuden | Butterfly Mode, Partial Expansion | Chips |
| Kakashi | one version | Lightning Blade, Kamui | Reading Icha Icha |
| Jiraiya | one version | Toad Summoning (Gamabunta), Rasengan | "Research" |
| Hinata | Part I | Byakugan, Gentle Fist | Cinnamon roll |
| Hinata | Shippuden | Byakugan, Eight Trigrams 64 Palms, Twin Lion Fists | Cinnamon roll |
| Tsunade | one version | Ground Smash, Mystic Palm, Katsuyu summoning | Sake |
| Itachi | one version | Crow Clone, Amaterasu, Susanoo (red) | Dango |

## Sprite format

- Base frames are **192×192** pixel art (Pet Therapy uses 50×50), feet on the bottom row.
   Part I characters are a bit shorter than the Shippuden versions, like on the sheet.
   Walking and jutsu face right. Players flip the frames horizontally when the pet walks left.
- Animations run at **10 fps**.
- Jutsu that need more room use a bigger canvas. The species JSON gives its size as a
   multiple of the base frame (`"size": [2.5, 1]`), same as Pet Therapy.
   The character keeps its 192×192 spot at the bottom left of that canvas.
   A few centred effects (Susanoo, Expansion, Butterfly Mode, Flower Storm, 64 Palms)
   move the character right; that offset is `anchorX` in `preview/manifest.js`, so a
   player can keep the pet from jumping when the effect starts.
- `human_bullet_tank` has `"isMoving": true`: Choji keeps travelling while it plays.

## How the animation works

Every frame is drawn from scratch by a skeleton rig with shoulders, elbows, hips and knees:

- **Walk:** a true side view, with legs stepping and arms swinging opposite to them.
- **Eating:** the bowl stays at the belly and the other hand travels to the mouth, solved
   with inverse kinematics. The mouth opens and chews.
- **Sleep:** lying down on the ground. **Drag:** dangling with arms flailing.
- **Jutsu:** real poses (hand signs, crouch, lunge, thrust, palm strikes) with effects on top.
- **Faces:** change with the action (angry brows, shouting, closed eyes, Sharingan, Byakugan,
   Sage eyes).

You can also replace any animation with hand-made or AI-made pose drawings in
`art/<id>/`. [docs/POSE_DRAWINGS.md](docs/POSE_DRAWINGS.md) explains how.

## Regenerating

Needs Python 3 with Pillow and NumPy.

```sh
python3 tools/sprites/build.py            # rebuild everything
python3 tools/sprites/build.py kakashi    # rebuild one character
```

How the generator is laid out:

- `extract_art.py`: cuts the figures out of the character sheet using rembg's isnet-anime model.
   You only need to run it again when the sheet changes. It needs a venv with `rembg[cpu]`.
- `engine.py`: canvas helpers: shapes, shading, outlines and a tiny pixel font for speech bubbles
- `body.py`: the sprite rig. Poses are joint angles or IK reach targets, and the feet stay on the ground.
   It also draws the anime face (eyes, brows, mouths), the clothing layers, side view and lying down.
- `characters.py`: one design per ninja, matched to the sheet (hair, headgear, outfit, colours, jutsu)
- `frames.py`: optional. It imports pose drawings from `art/<id>/` and replaces the generated animation for that id.
- `effects.py`: jutsu effects and props (rasengan, lightning, fire, Susanoo, shadows, toad, crows…)
- `anims.py`: the animations themselves, frame by frame
- `build.py`: writes PNGs, species JSON, strips and the manifest

To add a character, put a transparent PNG in `art/`. Then add a line to
`CHARACTERS` in `characters.py` with jutsu that already exist in `anims.JUTSU`
(or add a new builder there), and rebuild.

## Next steps

- Voice input (push-to-talk) for missions.
- Proactive check-ins: break reminders, calendar heads-ups.
