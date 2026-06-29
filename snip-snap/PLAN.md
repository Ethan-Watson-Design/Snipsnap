# Snipsnap — Product Planning

## What you're building

A free, native-feeling macOS capture tool. Screenshots, screen recording, FigJam-style annotations, and a passive voice log with retroactive "clip that" capture. Positioned against CleanShot X (too bloated), Shottr (no recording, not beautiful), and Xnapper (incomplete).

**Free. No paywall.**

---

## Locked Decisions

| Decision | Choice |
|----------|--------|
| **App name** | Snipsnap |
| **Bundle ID** | com.ethanwatson.snipsnap |
| **Min macOS** | 13.0 (Ventura) |
| **Distribution** | Direct (not App Store) |
| **Pricing** | Free |
| **Save location** | User picks during onboarding (no default) |
| **Default output** | Auto-copy to clipboard + save to folder + toast preview |
| **Toast behavior** | Click toast → opens annotation window |
| **Recording audio** | Screen only by default; mic opt-in; system audio opt-in |
| **Voice transcription** | Skip for now — audio file only |
| **Command bar hotkey** | ⌘6 / ⌘7 (default, fully remappable like Shottr) |
| **Menu bar** | Yes — no Dock icon, lives entirely in menu bar |

---

## Differentiator

| Competitor | Problem |
|------------|---------|
| macOS native | No recording, no annotations, no sharing |
| Shottr | No recording, functional but not beautiful |
| CleanShot X | Bloated, dated UI, subscription creeping in |
| Xnapper | Beautiful but incomplete, no recording |

**Snipsnap sits at the intersection nobody owns:** native-feeling, lightweight, genuinely beautiful, complete (screenshots + recording + voice), with annotations that don't get in the way — and a command bar no competitor has.

---

## Hotkeys (Shottr-style, all remappable)

| Action | Default |
|--------|---------|
| Command bar | ⌘6 |
| Full screen screenshot | ⌘⇧1 |
| Region screenshot | ⌘⇧2 |
| Window screenshot | ⌘⇧3 |
| Start/stop recording | ⌘⇧4 |
| Clip that (voice) | ⌘⇧5 |
| Open history | ⌘7 |

All hotkeys editable in Settings, stored in UserDefaults.

---

## Capture Bar (current, ⌘6)

Visual icon panel triggered by ⌘6. Six capture modes split across screenshot and recording groups, with camera/mic/system-audio/background toggles and a Capture button. Built as a floating `NSPanel`.

---

## Command Bar (future, ⌘6 or separate hotkey)

Spotlight-style text panel that coexists with or replaces the visual Capture Bar for power users. The idea: press the hotkey, type a short command, hit Return.

**Commands:**

| Input | Action |
|-------|--------|
| `region` | Region screenshot |
| `window` | Window picker |
| `full` | Full screen screenshot |
| `record` | Start/stop recording |
| `record window` | Window recording |
| `record region` | Region recording |
| `clip` | Clip last 60s of voice |
| `clip 30` | Clip last 30s |
| `timer 5` | 5s countdown then capture |
| `history` | Open capture library |
| `cam off` | Disable camera overlay |
| `mic on` / `mic off` | Toggle mic |

**UX design:**
- Borderless `NSPanel`, ~440px wide, centered top-quarter of screen (not bottom like the visual bar)
- Single `NSTextField` with a filtered results list below (max 5 results)
- Results update on each keystroke, first result auto-highlighted
- Return fires the top result; arrow keys navigate; Escape dismisses
- Each result row: icon (SF Symbol) + command name + keyboard shortcut if any
- Partial matching: typing `rec` surfaces `record`, `record window`, `record region`
- History of last 3 used commands surfaced when the field is empty

**Implementation notes:**
- Separate from `CaptureBar` — both can exist; Command Bar is an opt-in power-user layer
- Commands are a static array of `CommandEntry` structs with a name, aliases, SF symbol, and action closure
- Fuzzy match on name + aliases using simple `contains` or `levenshtein` threshold
- Close after any action fires (same as Escape)
- `CommandBar.swift` — new file, no dependency on `CaptureBar`

**Open question:** does ⌘6 toggle between the two, or does Command Bar get its own hotkey (e.g. ⌘Space-style with a user-defined key)?

---

## Post-Capture Flow

1. Capture fires (screenshot or clip)
2. File auto-saved to user's chosen folder
3. Image auto-copied to clipboard
4. Toast appears bottom-right (thumbnail + filename, 4s timeout)
5. Clicking toast → opens Annotation Window
6. Annotation Window: full capture with floating toolbar, FigJam-style
7. Escape or ✓ button → copies annotated version to clipboard, dismisses

---

## Annotation Design (FigJam-inspired)

**Principles:** tool appears near cursor, not in a distant toolbar. Switch modes with single key presses. Stroke weight and color follow recents.

| Key | Tool |
|-----|------|
| M | Marker (freehand) |
| H | Highlighter |
| A | Arrow |
| R | Rectangle |
| T | Text label |
| N | Number stamp (①②③) |
| B | Blur / redact |
| Cmd+Z | Undo |
| Escape | Finish + copy |

8 curated colors, no custom color picker in v1. No layers. No fill options. The goal is 10 seconds from capture to annotated clipboard.

---

## The Voice Feature ("Clip That")

**Concept:** Silent rolling audio buffer in memory. Hit ⌘⇧5 ("clip that") and it saves the last N seconds as an M4A file. Like Twitch clips for your own voice.

**Technical:**
- `AVAudioEngine` taps the mic into a circular ring buffer (never written to disk)
- "Clip that" → flush buffer to temp file → appear in history
- No transcription in v1
- Buffer duration: configurable (30 / 60 / 120s), default 60s

**Privacy:** a subtle dot on the menu bar icon indicates when the buffer is active. Nothing is ever uploaded. The buffer lives only in RAM.

---

## Recording Modes

| Mode | Default | Toggle in |
|------|---------|-----------|
| Screen video | On | Always on when recording |
| Mic audio | Off | Menu bar quick toggle or Settings |
| System audio | Off | Menu bar quick toggle or Settings |

All three are independent. Snipsnap asks for mic and system audio permissions only when the user turns those on.

---

## Tech Stack

**Swift + SwiftUI + AppKit**

| API | Use |
|-----|-----|
| ScreenCaptureKit | Screenshots + screen recording |
| AVFoundation | Video encoding |
| AVAudioEngine | Rolling voice buffer + mic recording |
| Speech framework | Transcription (future) |
| Core Graphics | Image processing |
| NSEvent global monitor | System-wide hotkeys |
| NSStatusItem | Menu bar |
| NSPanel | Overlay windows (region selector, command bar, toast, annotation) |
| UserDefaults | Hotkey preferences, settings |

---

## App Architecture

```
Snipsnap/
├── SnipsnapApp.swift             ✅ @main, AppDelegate, NSStatusItem, menu bar
├── RegionSelector.swift          ✅ Transparent overlay, crosshair, drag-to-select
├── ScreenshotEngine.swift        ✅ ScreenCaptureKit capture, coordinate conversion
├── ToastView.swift               ✅ Bottom-right preview toast, tap to annotate/reveal
├── AnnotationWindow.swift        ✅ Full annotation suite, smooth strokes, select/drag, emoji, toolbar
├── RecordingEngine.swift         ✅ ScreenCaptureKit + AVFoundation H.264 MP4
├── VideoAnnotationWindow.swift   ✅ AVPlayerView, annotate frame, reveal in Finder
├── CaptureBar.swift              ✅ Floating capture mode panel (⌘6), all modes + camera/mic/audio toggles
├── CaptureHistory.swift          ✅ In-memory + on-disk capture history, JSON manifest
├── CaptureLibraryWindow.swift    ✅ NavigationSplitView history panel — sidebar list + detail preview
├── SettingsWindow.swift          ✅ Save location picker, read-only shortcut badges
│
│   — TO BUILD —
├── AudioRingBuffer.swift         # AVAudioEngine tap → circular buffer in RAM
├── ClipEngine.swift              # Flush buffer → M4A on "clip that"
└── CommandBar.swift              # Future: Spotlight-style text command panel
```

**Info.plist — required keys:**
- `LSUIElement = true` → hides Dock icon, menu bar only
- `NSScreenCaptureUsageDescription` → screen recording permission string
- `NSMicrophoneUsageDescription` → mic permission string
- `NSAppleEventsUsageDescription` → if needed for accessibility

---

## Feature Roadmap

### v0.1 — Core screenshot loop ✅
Region screenshot, toast notification, and clipboard capture are all wired up via ScreenCaptureKit with correct display-relative coordinates. Global hotkeys (⌘⇧2, ⌘⇧4, ⌘6) live via NSEvent global monitor with accessibility permission gating.

### v0.1.5 — Hotkeys (partial ✅)
⌘⇧2 and ⌘⇧4 are live via NSEvent global monitor, with accessibility permission gating and a guard against double-triggering recording.
- [ ] ⌘⇧1 → full screen screenshot (wire in global monitor + CaptureBar execute)
- [ ] ⌘⇧3 → window screenshot (wire in global monitor + CaptureBar execute)
- [ ] ⌘7 → open capture library (wire in global monitor + AppDelegate)
- [ ] Better onboarding UX for accessibility permission

### v0.2 — Annotations ✅
Full annotation suite ships in `AnnotationWindow.swift` — marker, highlighter, arrow, rectangle, text, number stamps, key-driven tool switching, 8-color palette, undo, and a floating pill toolbar.
- [ ] Blur / redact region (deferred)

---

## Upcoming Priorities

### v0.3 — Annotation upgrades ✅
Added emoji stamp tool (E key) with searchable picker, select tool (S key) with drag-to-reposition and delete, and a dashed bounding box selection visual.
- [ ] Stroke pressure simulation — vary lineWidth based on mouse speed
- [ ] Blur / redact region tool (B key)
- [ ] Snap-to guides when drawing arrows and rectangles near edges

### v0.4 — Video previewer + recording annotation ✅
`VideoAnnotationWindow.swift` opens from recording toast with play/pause scrubber, and "Annotate Frame" grabs the current frame into `AnnotationWindow`.
- [ ] Record selected region (not just full screen)
- [ ] Audio toggles: mic on/off, system audio on/off

### v0.5 — Capture Bar ✅
`CaptureBar.swift` is a floating bottom panel (⌘6) covering screenshot, record, and voice clip modes with active state highlighting and Escape to dismiss.
- [ ] Options popover (mic toggle, system audio, timer, save location)

### v0.5.5 — Settings ✅
`SettingsWindow.swift` launched with save location picker and read-only shortcut badges. Output folder preference stored in UserDefaults via `AppSettings`.
- [ ] Wire save location into screenshot export — `CaptureHistory.saveScreenshot` currently ignores `AppSettings.destinationFolderURL` and always saves to Application Support
- [ ] Remappable hotkeys (future)

### v0.6 — Loom-style recording with camera ✅
Floating circular camera bubble composited into the MP4 via GPU-backed CIContext, with mic support, feathered mask, selfie mirror, and camera/mic toggles in CaptureBar.
- [ ] Draggable camera bubble position baked into composite (currently always bottom-right regardless of bubble position)
- [ ] Camera bubble size presets (Small / Medium / Large)

### v0.7 — History ✅ (partial)
`CaptureLibraryWindow.swift` ships as a NavigationSplitView with sidebar list + detail preview pane. Accessible via "Show All…" in the menu bar. Screenshots and recordings both shown; right-click → Show in Finder / Move to Trash.
- [ ] Wire ⌘7 hotkey to open the library
- [ ] Re-open screenshot for annotation from the library (currently only works from toast)
- [ ] Scrolling capture
- [ ] OCR — copy text from screenshot (Vision framework)

### v0.8 — Onboarding
No onboarding exists yet. First launch silently falls back to Desktop for save location. This is the first impression — design it well.
- [ ] First-launch flow: request screen recording permission → request accessibility permission → pick save folder
- [ ] Each step is a single focused sheet, not an alert dump
- [ ] Don't proceed to the next step until the prior permission is granted (poll + retry)
- [ ] Save folder step: show a picker with a suggested default (~/Desktop or ~/Screenshots), let user change it, persist to `AppSettings`

### v1.0 — Launch
- [ ] Full screen + window screenshot modes wired up (⌘⇧1, ⌘⇧3)
- [ ] App icon
- [ ] Notarization
- [ ] Website / download page

---

## Future / Post-v1
- Voice "Clip That" — rolling audio buffer, ⌘⇧5 to clip last N seconds (`AudioRingBuffer.swift` + `ClipEngine.swift`)
- Command Bar (`CommandBar.swift`) — Spotlight-style text panel, power-user layer on top of the visual Capture Bar
- Loom-style hosted sharing (upload + shareable URL)
- Remappable hotkeys in Settings
- Blur / redact annotation tool (B key, deferred from v0.2)
- Snap-to guides in annotation canvas
- Camera bubble drag position baked into recording composite (currently always bottom-right)
- Camera bubble size presets (Small / Medium / Large)

---

## Permissions Flow (design this well — it's the first impression)

| Permission | Trigger | Dialog copy suggestion |
|------------|---------|----------------------|
| Screen Recording | First launch | "Snipsnap needs screen access to capture screenshots and recordings. Nothing is ever uploaded without your action." |
| Accessibility | First launch | "Needed so your keyboard shortcuts work from any app." |
| Microphone | When voice buffer is turned on | "Snipsnap keeps a short audio buffer in memory so you can clip the last 60 seconds. It's never saved or uploaded until you clip it." |
| System audio | When system audio recording toggled on | Standard macOS prompt — no custom copy needed |

---

## Cursor Prompting Notes (for when you start building)

- **Always give Cursor the file path and class name you want it to work in.** Vague prompts produce generic code.
- **Paste in the architecture tree above** when starting a new file so Cursor knows where it fits.
- **For SwiftUI + AppKit bridging**, Cursor tends to mix them incorrectly — specify which layer you're working in.
- **ScreenCaptureKit is newer API** — Cursor may suggest deprecated CGWindowList approaches. Correct it: "Use ScreenCaptureKit, not CGWindowList."
- **For the ring buffer**, ask Cursor to implement `AVAudioEngine.inputNode.installTap` with a circular array — specify you don't want it to write to disk.
- **Hotkey registration**: NSEvent.addGlobalMonitorForEvents requires Accessibility permission. Cursor may forget to check for this.
