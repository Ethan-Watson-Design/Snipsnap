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

## Priority Use Cases & Competitive Positioning (2026-07-04)

**Use cases Snipsnap is built for, in priority order:**

| # | Use case | What it needs from annotation |
|---|----------|-------------------------------|
| 1 | Bug reports / QA feedback | Precise pointing at the broken element, redaction of sensitive data, fast |
| 2 | Design/UX feedback | Text anchored to an exact region ("increase width to 150px"), often several comments per screenshot |
| 3 | Marketing / external sharing | Polished, on-brand, clean output for public posting |

Deprioritized for now: tutorial/step-by-step documentation (needs numbered step badges, a different primitive) and fast text-less support replies.

**Competitors tracked most closely, in priority order:**

| Competitor | Relevance | Their answer to "focus attention" |
|---|---|---|
| CleanShot X | Closest direct competitor — same category (Mac screenshot annotation), same target user | Dedicated Spotlight tool (dim outside a region) + separate Highlight tool. The bar to beat. |
| Loom | Reference point for the recording side, not annotation | Live cursor-follow spotlight during recording only — doesn't apply to static capture, not a real competitor on this feature |
| FigJam | Reference point for whiteboard-style annotation UX (hover-based tool appearance, bendable connectors) | No dedicated tool — "draw a generic shape yourself." This is the gap Snipsnap's Spotlight tool fills in the screenshot category |

**Design decisions this produced:**
- No dedicated rigid arrow-only primitive. Explain-focused use cases (2, part of 1) are served by anchored text/callouts; point-focused use cases (1, 3) are served by Rectangle/Highlighter (circle-the-region) plus the new Spotlight tool below — arrow semantics (directional pointing) weren't actually the load-bearing need once the three use cases were made explicit.
- Spotlight ships with all three suppression techniques (dim / blur / desaturate) as a per-annotation setting rather than picking one — precision-first use cases (1, 2) favor Dim + hard edge; polish-first use case (3) is the one place Blur or Desaturate earn their extra cost.

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

> **⚠️ Deviation found (2026-07-04 eval):** `SnipsnapApp.swift`'s `registerGlobalHotkeys()` does not match this table. Only three global hotkeys actually exist: **⌘⇧3 → region screenshot** (not window — `takeScreenshot()` opens `RegionSelector`), **⌘⇧4 → start/stop recording** (correct), and **⌘6 → Capture Bar** (correct). There is no live global binding for ⌘⇧1 (full screen), ⌘⇧2 (region, per this table), or ⌘7 (history) anywhere in the codebase — confirmed via full-repo search. Full-screen and window screenshot capture *do* work, but only through the Capture Bar UI (⌘6 → click a mode), not as direct hotkeys. Either the table or `SnipsnapApp.swift` needs to change — right now they disagree.

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
| F | Focus / Spotlight |
| Cmd+Z | Undo |
| Escape | Finish + copy |

8 curated colors, no custom color picker in v1. No layers. No fill options. The goal is 10 seconds from capture to annotated clipboard.

---

## Bendable Arrow Tool (FigJam-style elbow)

Arrow starts as a straight line (unchanged default behavior). When selected, it shows a handle at its midpoint that can be dragged to bend the line into two straight segments with a soft rounded joint — same idea as FigJam's connector bend, minus auto-routing (this is Option 1 from the arrow-tool exploration: fixed single bend, user-controlled, not a full multi-point polyline).

**Behavior:**
- Default: straight `from → to`, arrowhead at `to` — same as today.
- Select tool: a draggable handle appears at the current bend point (or the line's midpoint if no bend yet).
- Dragging that handle creates/moves the bend; line becomes `from → bend → to` with a rounded corner.
- Double-click the arrow (or its bend handle) → clears the bend, snaps back to straight.
- Endpoint dragging (start/end) and tip style behavior are unchanged.

**Data model:** `Annotation.arrow` gains an optional `bend: CGPoint?` (`nil` = straight, current behavior).

- [x] Implement in `AnnotationWindow.swift` — done. `arrowBendHandle`, `appendArrowShaft`, and the drag-handle/rounded-joint/double-click-to-reset behavior are all in place and match this spec exactly.

---

## Focus / Spotlight Tool

Draws attention to a region without a pointer or text — the "hey, look over here" tool identified as the gap in FigJam/Miro/draw.io (generic shapes only, no dedicated tool) and matched against CleanShot X (has it, the bar to beat). Same drag-to-define interaction as Rectangle (`R`) and `RegionSelector`; press `F`, drag out the region, release.

**Behavior:**
- On release, the floating pill toolbar shows a 3-icon technique picker (Dim / Blur / Desaturate) in place of the color swatches
- Default technique: **Dim** — cheapest to render, matches CleanShot X's baseline, best fit for the two precision-first use cases (bug reports, design feedback)
- Region renders as a rounded rectangle with a **hard-edge cutout** — no feather/vignette in v1. Precision beats polish for 2 of the 3 priority use cases; the one case where a soft edge would help (marketing) isn't worth the added rendering complexity yet
- Last technique used is remembered for the next Spotlight annotation (same "recents" principle already used for stroke weight/color)
- Selecting a placed Spotlight annotation shows the same drag-handle bounding box as the `S` select tool, for resize/reposition
- Switching technique on an existing annotation re-renders live — no redraw needed
- Escape / ✓ commits like every other tool

**Data model:** `Annotation.spotlight` — `region: CGRect`, `technique: SpotlightTechnique` (`.dim | .blur | .desaturate`), fixed `cornerRadius` (not user-exposed in v1)

**Rendering — all three lean on the GPU-backed `CIContext` pipeline already used for camera-bubble compositing (`RecordingBackgroundRenderer`/`ShipItPanel`), no new pipeline needed:**
- **Dim**: ~45% black overlay composited everywhere outside `region` (clip-invert mask)
- **Blur**: `CIGaussianBlur` on a full-image copy; sharp original composited back in only inside `region`
- **Desaturate**: `CIColorControls` with `saturation: 0` applied outside `region`, full color preserved inside

Not in v1: feathered/vignette edge, non-rectangular spotlight shapes.

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
├── ShipItPanel.swift             ✅ Undocumented until now — recording export panel: side-by-side compare,
│                                     background-style swatches for the recording composite
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
Region screenshot, toast notification, and clipboard capture are all wired up via ScreenCaptureKit with correct display-relative coordinates. Global hotkeys (⌘⇧3 for region — see deviation note above, ⌘⇧4, ⌘6) live via NSEvent global monitor with accessibility permission gating.

### v0.1.5 — Hotkeys (partial ✅)
**Corrected 2026-07-04:** the live global hotkeys are actually ⌘⇧3 (region screenshot, mislabeled — see deviation note above), ⌘⇧4 (recording), and ⌘6 (Capture Bar), gated by accessibility permission with a guard against double-triggering recording.
- [ ] ⌘⇧1 → full screen screenshot (capture logic exists via `CaptureBar`'s `.screenshotFullScreen` mode; global hotkey not wired)
- [ ] ⌘⇧2 → region screenshot per the Hotkeys table above (currently fires on ⌘⇧3 instead — reconcile table vs code)
- [ ] ⌘⇧3 → window screenshot per the Hotkeys table above (capture logic exists via `CaptureBar`'s `.screenshotWindow` mode; global hotkey not wired — that combo is currently taken by region capture)
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
- [ ] Focus / Spotlight tool (F key) — dim/blur/desaturate technique picker, see Focus / Spotlight Tool spec above
- [ ] Snap-to guides when drawing arrows and rectangles near edges

### v0.4 — Video previewer + recording annotation ✅
`VideoAnnotationWindow.swift` opens from recording toast with play/pause scrubber, and "Annotate Frame" grabs the current frame into `AnnotationWindow`.
- [x] Record selected region (not just full screen) — done. `CaptureBar`'s `.recordRegion` mode calls `executeRecording(captureTarget: .region(rect), ...)`.
- [x] Audio toggles: mic on/off, system audio on/off — done. `CaptureBar` has `micEnabled`/`systemAudioEnabled` state wired through to `executeRecording`, with a popover menu for system audio and a mic device picker.

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
- [x] Re-open screenshot for annotation from the library — done. The preview pane's "Open" button (⏎) calls `CaptureLibraryWindow.open(entry)`, which routes screenshots into `AnnotationWindow` and recordings into `VideoAnnotationWindow`.
- [ ] Scrolling capture
- [ ] OCR — copy text from screenshot (Vision framework)

### v0.8 — Onboarding
No onboarding exists yet. First launch silently falls back to Desktop for save location. This is the first impression — design it well.
- [ ] First-launch flow: request screen recording permission → request accessibility permission → pick save folder
- [ ] Each step is a single focused sheet, not an alert dump
- [ ] Don't proceed to the next step until the prior permission is granted (poll + retry)
- [ ] Save folder step: show a picker with a suggested default (~/Desktop or ~/Screenshots), let user change it, persist to `AppSettings`

### v1.0 — Launch
- [ ] Full screen + window screenshot modes wired up as **global hotkeys** (⌘⇧1, ⌘⇧3) — the capture logic itself is done (`CaptureBar` modes work today via ⌘6 → click); only the dedicated hotkey binding is missing
- [ ] App icon (`snipsnap-icon.svg` exists at repo root, not yet wired into `Assets.xcassets/AppIcon.appiconset`, which is still empty of icon files)
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

## Design System Consistency (evaluation, 2026-07-04)

There's no shared design-tokens file. Each window/panel defines its own private `Style` enum with its own numbers, so values that should be identical drift silently:

- **Corner radii vary with no evident pattern**: 4 (`CaptureLibraryWindow`, arrow selection handles), 5 (`SettingsWindow`), 6 (toast, several `AnnotationWindow` chips), 8 (`CaptureBar` hover state, one `ShipItPanel` element), 10 (`CaptureBar` panel, `RecordingBackgroundPreviewWindow`), 12 (toast panel, `CaptureBar` outer panel, `ShipItPanel` outer panel, several `AnnotationWindow` panels). Similar-purpose surfaces (a floating panel vs. a floating panel) don't consistently share a radius.
- **The recording-background brand palette is duplicated as raw literals** in two places — `RecordingBackgroundRenderer.swift` (SwiftUI `Color(red:green:blue:)`) and `ShipItPanel.swift` (`NSColor(red:green:blue:alpha:)`) — with the same five RGB triples typed out independently instead of referencing one shared constant. If the palette changes, it's easy to update one file and miss the other.
- **Two different color-definition conventions coexist**: semantic system colors (`NSColor.separatorColor`, `.controlAccentColor`, `.quaternaryLabelColor`) are used freely, alongside custom brand colors defined ad hoc (`NSColor.annotationSelectionAccent`, `.regionSelectionAccent` as an extension in `AnnotationWindow.swift`, plus the raw literals above). No single palette file ties these together.
- **Typography is mostly hand-set AppKit `NSFont.systemFont(ofSize:weight:)` calls** (sizes 9.5, 11, 12, 13, 14, 18 appear across files with no named scale), **except `CaptureLibraryWindow.swift`**, which is built in SwiftUI and uses semantic Dynamic Type fonts (`.headline`, `.caption`) instead. That one window will respond to Dynamic Type / accessibility text-size changes differently than every other window in the app, and its type sizing won't necessarily match the fixed-pixel sizes used elsewhere.
- **`ShipItPanel.swift` is a real, shipped file** (recording export panel — side-by-side compare view, background-style swatches) **that was missing from the App Architecture list entirely** until this pass. Worth folding into the architecture doc so it isn't orphaned from planning.

None of this breaks anything today, but it's the kind of drift that gets expensive right around v1.0 polish — recommend a `DesignTokens.swift` (or similar) centralizing corner radii, the brand palette, and a small type scale before the launch push.

---

## Cursor Prompting Notes (for when you start building)

- **Always give Cursor the file path and class name you want it to work in.** Vague prompts produce generic code.
- **Paste in the architecture tree above** when starting a new file so Cursor knows where it fits.
- **For SwiftUI + AppKit bridging**, Cursor tends to mix them incorrectly — specify which layer you're working in.
- **ScreenCaptureKit is newer API** — Cursor may suggest deprecated CGWindowList approaches. Correct it: "Use ScreenCaptureKit, not CGWindowList."
- **For the ring buffer**, ask Cursor to implement `AVAudioEngine.inputNode.installTap` with a circular array — specify you don't want it to write to disk.
- **Hotkey registration**: NSEvent.addGlobalMonitorForEvents requires Accessibility permission. Cursor may forget to check for this.
