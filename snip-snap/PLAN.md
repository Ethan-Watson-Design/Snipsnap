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

## Command Bar

Spotlight-style panel triggered by ⌘6. Type to run any action:

- `region` → region screenshot
- `window` → window picker
- `full` → full screen
- `record` → start recording
- `clip` → clip last 60s of voice
- `clip 30` → clip last 30s
- `timer 5` → 5s countdown then capture
- `history` → open capture history

Implemented as a borderless `NSPanel` with a `TextField` and filtered results list. Closes on Escape or after any action fires.

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
├── SnipsnapApp.swift           ✅ @main, AppDelegate, NSStatusItem, menu bar, CaptureHistory
├── RegionSelector.swift        ✅ Transparent overlay, crosshair, drag-to-select
├── ScreenshotEngine.swift      ✅ ScreenCaptureKit capture, coordinate conversion
├── ToastView.swift             ✅ Bottom-right preview toast, tap to annotate/reveal
├── AnnotationWindow.swift      ✅ Full annotation suite, smooth strokes, select/drag, emoji, toolbar
├── RecordingEngine.swift       ✅ ScreenCaptureKit + AVFoundation H.264 MP4
├── VideoAnnotationWindow.swift ✅ AVPlayerView, annotate frame, reveal in Finder
├── CaptureBar.swift            ✅ Floating capture mode bar (⌘6), all modes
├── SettingsWindow.swift        ✅ Lightweight settings, read-only shortcut badges
│
│   — TO BUILD —
├── AudioRingBuffer.swift       # AVAudioEngine tap → circular buffer in RAM
├── ClipEngine.swift            # Flush buffer → M4A on "clip that"
└── HistoryView.swift           # All captures in one place
```

**Info.plist — required keys:**
- `LSUIElement = true` → hides Dock icon, menu bar only
- `NSScreenCaptureUsageDescription` → screen recording permission string
- `NSMicrophoneUsageDescription` → mic permission string
- `NSAppleEventsUsageDescription` → if needed for accessibility

---

## Feature Roadmap

### v0.1 — Core screenshot loop ✅
- [x] Xcode project: Snipsnap, SwiftUI, LSUIElement = true
- [x] NSStatusItem menu bar (icon + dropdown menu) — `SnipsnapApp.swift`
- [ ] Global hotkeys wired (NSEvent addGlobalMonitorForEvents)
- [ ] Full screen screenshot → clipboard + save
- [ ] Window screenshot (SCShareableContent window picker)
- [x] Region selector overlay (borderless NSPanel + crosshair drawing) — `RegionSelector.swift`
- [x] Toast notification (bottom-right, 4s, click to annotate) — `ToastView.swift`
- [x] Screenshot capture → clipboard (ScreenCaptureKit) — `ScreenshotEngine.swift`
- [x] Coordinate fix: display-relative + Y-flip for ScreenCaptureKit sourceRect

### v0.1.5 — Hotkeys (partial ✅)
- [x] ⌘⇧2 → region screenshot (global monitor via NSEvent)
- [x] ⌘⇧4 → start recording
- [x] Accessibility permission request + polling until granted
- [x] Guard against triggering recording while one is in progress (isStartingRecording flag)
- [ ] ⌘⇧1 → full screen screenshot (engine not built yet)
- [ ] ⌘⇧3 → window screenshot (engine not built yet)
- [ ] Better onboarding UX for accessibility permission

### v0.2 — Annotations ✅
- [x] Annotation window opens from toast click — `AnnotationWindow.swift`
- [x] Smooth freehand marker (quadratic bezier midpoint smoothing)
- [x] Highlighter tool (semi-transparent, lineWidth 14)
- [x] Arrow tool (drag, filled arrowhead)
- [x] Rectangle tool (rounded rect, stroke only)
- [x] Text label tool (inline NSTextField, commits on Enter)
- [x] Number stamp (①②③ auto-incrementing, click to place)
- [x] Key-driven tool switching (M, H, A, R, T, N)
- [x] 8-color palette with active swatch indicator
- [x] Cmd+Z undo
- [x] Escape → flatten + copy to clipboard + close
- [x] Copy button in toolbar
- [x] Floating pill toolbar (NSVisualEffectView, SF Symbols)
- [ ] Blur / redact region (deferred to v0.6)

---

## Upcoming Priorities

### v0.3 — Annotation upgrades ✅
- [x] Emoji stamp tool (E key) — picker with 12 default emoji, searchable, click to place
- [x] White outline on emoji stamps (white glow shadow via CGContext)
- [x] Select tool (S key) — click to select any annotation
- [x] Drag selected annotation to reposition
- [x] Delete key removes selected annotation
- [x] Selection visual (blue dashed bounding box)
- [ ] Stroke pressure simulation — vary lineWidth based on mouse speed
- [ ] Blur / redact region tool (B key)
- [ ] Snap-to guides when drawing arrows and rectangles near edges

### v0.4 — Video previewer + recording annotation ✅
- [x] `VideoAnnotationWindow.swift` — AVPlayerView + "Annotate Frame" button
- [x] Play/pause controls + time scrubber (AVPlayerView inline controls)
- [x] Recording toast tap → opens VideoAnnotationWindow
- [x] "Annotate Frame" grabs current frame → opens AnnotationWindow
- [x] "Reveal in Finder" button
- [ ] Record selected region (not just full screen)
- [ ] Audio toggles: mic on/off, system audio on/off

### v0.5 — Capture Bar ✅
- [x] `CaptureBar.swift` — borderless floating panel centered at bottom of screen
- [x] Screenshot: Region · Window · Full Screen modes
- [x] Record: Full Screen · Region modes
- [x] Voice Clip mode
- [x] Active mode highlighted with selected state
- [x] Capture/Record trigger button
- [x] ⌘6 → show CaptureBar
- [x] Escape to dismiss
- [ ] Options popover (mic toggle, system audio, timer, save location)

### v0.5.5 — Settings ✅
- [x] `SettingsWindow.swift` — lightweight settings window
- [x] Read-only shortcut display (⌘⇧2, ⌘⇧4, ⌘⇧5) with key badge UI
- [x] "Settings…" menu item in menu bar
- [ ] Remappable hotkeys (future)
- [ ] Output folder picker (future)

### v0.6 — Loom-style recording with camera ✅
- [x] `CameraPreviewWindow.swift` — floating circular camera bubble, draggable, AVCaptureVideoPreviewLayer, circular CAShapeLayer mask, drop shadow
- [x] Camera + mic toggles in CaptureBar — show only when Record mode is selected
- [x] `RecordingEngine` mic audio support — AVCaptureAudioDataOutput → AAC audio track in MP4
- [x] Camera compositing baked into MP4 — GPU-backed CIContext, pixel buffer adaptor, thread-safe latestCameraFrame with NSLock
- [x] Horizontal mirror on camera feed (selfie convention)
- [x] 2px feathered circular mask via CIRadialGradient + CIBlendWithMask
- [x] CISourceOverCompositing — camera circle rendered bottom-right corner, 20pt margin
- [x] CaptureBar.shared exposes camera/mic state to RecordingEngine before startRecording fires
- [ ] Draggable camera bubble position baked into composite (currently always bottom-right regardless of bubble position)
- [ ] Camera bubble size presets (Small / Medium / Large)

### v0.7 — History + settings
- [ ] Unified history panel (⌘7) — screenshots and recordings in one view
- [ ] Re-open any capture for annotation
- [ ] Scrolling capture
- [ ] OCR — copy text from screenshot (Vision framework)
- [ ] Output folder picker in Settings (instead of always saving to Desktop)

### v1.0 — Launch
- [ ] Polished onboarding (permission request flow — this is the first impression)
- [ ] Full screen + window screenshot modes wired up (⌘⇧1, ⌘⇧3)
- [ ] App icon
- [ ] Notarization
- [ ] Website / download page

---

## Future / Post-v1
- Voice "Clip That" — rolling audio buffer, ⌘⇧5 to clip last N seconds
- Loom-style hosted sharing (upload + shareable URL)
- Remappable hotkeys in Settings
- Blur / redact annotation tool
- Snap-to guides in annotation canvas

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
