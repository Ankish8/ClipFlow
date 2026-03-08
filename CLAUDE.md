# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building and Running
```bash
# Build debug version (SPM)
swift build

# Build release version
swift build --configuration release

# Run the application
./.build/debug/ClipFlow

# Clean build artifacts
swift package clean

# Generate Xcode project (required after cloning)
xcodegen generate
```

### Dual Build System
- **xcodegen** (`project.yml`) is the source of truth for Xcode project settings. `ClipFlow.xcodeproj` is gitignored — regenerate with `xcodegen generate`.
- **Package.swift** is maintained for `swift build` CLI compatibility.
- Both target **macOS 26** (Swift tools version 6.2).

### Critical Build Flags (ClipFlow target)
- `-parse-as-library` — required because `main.swift` uses `@main struct ClipFlowApp`, which conflicts with Swift's special entry-point treatment of `main.swift`
- `DISABLE_SENDABLE_CHECKING` — migration flag for Swift 6 strict concurrency
- `ENABLE_DEBUG_DYLIB = YES` — enables SwiftUI Previews (xcodegen only)

### Testing
No formal test suite. Manual testing: build and run, verify clipboard monitoring, overlay (⌥⌘V), menu bar, and accessibility permissions.

## Architecture Overview

### Module Dependency Graph
```
ClipFlow (executable — UI, AppDelegate, views, managers)
    ↓
ClipFlowBackend (services — ClipboardService, StorageService, monitoring, cache, tags, OCR)
    ↓
ClipFlowAPI (protocols — ClipboardServiceAPI, HistoryFilter, TransformAction)
    ↓
ClipFlowCore (models — ClipboardItem, ClipboardContent, Collection, Tag, ItemMetadata)
```
External deps: GRDB (SQLite), KeyboardShortcuts (global hotkey)

### Core Data Flow
1. **ClipboardMonitorService** polls `NSPasteboard` every 150ms (configurable via `pollingInterval` UserDefaults key), detecting changes via `changeCount`
2. **StorageService** persists to SQLite via GRDB (`DatabaseRecords.swift` maps domain models ↔ database records)
3. **ClipboardService** coordinates monitoring, storage, and exposes Combine publishers (`PassthroughSubject`/`CurrentValueSubject`) consumed by UI
4. **ClipboardViewModel** subscribes to publishers and drives SwiftUI views
5. **MenuBarManager** / **OverlayManager** handle UI presentation; **AccessibilityManager** manages macOS permissions

### Inter-Manager Communication
Managers communicate via `NotificationCenter` notifications (not direct calls):
- `.showClipboardOverlay` / `.hideClipboardOverlay` — toggle overlay visibility
- `.navigateOverlayLeft` / `.navigateOverlayRight` — arrow key card navigation
- `.navigateOverlayLeftExtend` / `.navigateOverlayRightExtend` — shift+arrow multi-select
- `.toggleQuickLook` — spacebar Quick Look preview

### Overlay Window Architecture
The overlay is an **NSPanel** (not NSWindow) with `[.borderless, .nonactivatingPanel]` style:
- **Non-activating**: becomes key without stealing focus from the user's active app
- **Slide-up animation**: from below screen to `screen.visibleFrame` bottom with spring timing
- **`ClipboardOverlayWindow.sendEvent(_:)`** intercepts keyboard events before SwiftUI text fields consume them (arrow keys, spacebar, number keys, Enter, Escape)
- **`BorderlessHostingView`**: strips focus rings and borders that AppKit adds to NSHostingView
- **Click-outside dismiss**: dual event monitors (local + global) detect clicks outside the panel
- **Focus restoration**: captures `NSWorkspace.shared.frontmostApplication` before showing, restores on hide

### Liquid Glass (macOS 26)
The overlay uses `NSGlassEffectView` for Liquid Glass compositing:
- Window must be key (`makeKeyAndOrderFront`) for live glass rendering
- Cards use `Color.primary.opacity(0.07)` fill — not `.regularMaterial` (avoids double-blur)
- Collection behavior: `[.canJoinAllSpaces, .fullScreenAuxiliary]` — no `.stationary` (would freeze glass after ~2s)

### Settings Window Pattern (LSUIElement App)
Since ClipFlow runs as `NSApp.setActivationPolicy(.accessory)` (no dock icon), settings requires special handling:
- Temporarily switch to `.regular` activation policy (shows dock icon) so window survives click-away
- Revert to `.accessory` in `windowWillClose`
- Uses `NavigationSplitView` (not `TabView`, which breaks in NSHostingView)
- Window level must be `.normal` (not `.floating` — floating breaks window tiling on macOS 26)

### Application Lifecycle
`AppDelegate.applicationDidFinishLaunching` initializes in sequence:
1. `NSApp.setActivationPolicy(.accessory)` — hide dock icon
2. Initialize managers (all singletons: `.shared`)
3. Check/request accessibility permissions
4. Start clipboard monitoring with configured polling interval
5. Run auto-delete cleanup (based on `autoDeleteAfterDays` UserDefaults)
6. Warm cache, start 30s performance metric logging loop

## Content Type System
Polymorphic `ClipboardContent` enum in ClipFlowCore. Detection in `ClipboardMonitorService` via NSPasteboard type checking:
- Text → `TextContent` (with email/phone/URL metadata detection via `String+ContentDetection`)
- Images → `ImageContent` (dimensions, format, thumbnail generation)
- Files → `FileContent` (from Finder, with size/type)
- Rich text → `RichTextContent` (preserves formatting)
- URLs → `LinkContent` (with async metadata fetching via `LinkMetadataService`)
- Code → language detection via `String+ContentDetection`
- Colors → hex conversion

## Key Services
- **TagService** / **AutoTagService**: user-defined and rule-based tagging of clipboard items
- **OCRService**: text extraction from image clipboard items
- **SoundManager**: per-event sound effects with user-configurable toggles
- **CacheManager**: multi-level (memory + disk) caching with configurable size limits
- **PerformanceMonitor**: runtime metrics logging

## Important Constraints

### Concurrency Model
- All UI managers are `@MainActor` isolated
- Clipboard monitoring on background queues, publishes to MainActor via Combine
- `DISABLE_SENDABLE_CHECKING` flag active during Swift 6 migration
- Careful `async`/`await` patterns required throughout

### Privacy
`ClipboardMonitorService` checks for concealed/transient pasteboard types to skip password manager data and sensitive content.

### Permission Requirements
Accessibility permissions required for: global hotkey (⌥⌘V), cross-app paste, clipboard monitoring.
