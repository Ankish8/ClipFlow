# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Building and Running
```bash
# Build debug version
swift build

# Build release version
swift build --configuration release

# Run the application
./.build/debug/ClipFlow

# Clean build artifacts
swift package clean
```

### Project Structure Commands
The project uses Swift Package Manager with modular architecture. Each module has specific responsibilities and dependencies flow in one direction.

## Architecture Overview

### Module Structure and Dependencies
ClipFlow uses a layered architecture with clear separation of concerns:

```
ClipFlow (executable)
    ↓ depends on
ClipFlowBackend (services layer)
    ↓ depends on
ClipFlowAPI (protocols/interfaces)
    ↓ depends on
ClipFlowCore (models/data structures)
```

### Key Architectural Patterns

**Actor-Based Concurrency**: Uses @MainActor classes for UI components and data race prevention. ClipboardMonitorActor was converted to @MainActor class to resolve Swift 6 concurrency issues.

**Protocol-Oriented Design**: ClipboardServiceAPI defines the contract for clipboard operations, implemented by ClipboardService in the backend layer.

**Reactive Publishers**: Uses Combine framework with PassthroughSubject and CurrentValueSubject for real-time updates between clipboard monitoring and UI components.

**Menu Bar Application**: Runs as NSApplication.accessory (no dock icon) with:
- Menu bar status item for quick access
- Global hotkey overlay (⌥⌘V) via KeyboardShortcuts library
- SwiftUI views embedded in AppKit infrastructure

### Core Data Flow

1. **ClipboardMonitorService** polls NSPasteboard every 100ms
2. **StorageService** persists items using GRDB.swift SQLite database
3. **ClipboardService** coordinates between monitoring, storage, and UI
4. **MenuBarManager/OverlayManager** handle UI presentation
5. **AccessibilityManager** manages macOS permissions for global hotkeys

### Critical Implementation Details

**Concurrency Model**: All UI managers are @MainActor isolated. Clipboard monitoring happens on background actors but publishes updates to MainActor for UI consumption.

**Permission Requirements**: Requires accessibility permissions for:
- Global hotkey registration (⌥⌘V)
- Cross-application paste functionality
- Clipboard monitoring across all apps

**Database Schema**: Uses GRDB with custom record types (ClipboardItemRecord) that map to/from domain models (ClipboardItem).

**Content Type System**: Polymorphic ClipboardContent enum supports text, images, files, links, code, colors, and multi-content items with metadata extraction.

### Security and Privacy

**V1 Simplified Security**: Security features were removed from v1 implementation to reduce complexity. SecurityMetadata struct exists but is empty.

**Privacy Compliance**: Checks for concealed/transient clipboard types to avoid capturing password manager data.

## Important Constraints

### Swift 6 Concurrency
- Uses strict concurrency checking with DISABLE_SENDABLE_CHECKING flag
- Requires careful @MainActor annotation for UI components
- Actor isolation errors require await/async patterns throughout

### macOS Integration
- Minimum macOS 15 target
- Uses AppKit for menu bar and accessibility features
- SwiftUI for modern UI components within AppKit framework
- KeyboardShortcuts library for global hotkey support

### Performance Requirements
- Sub-100ms clipboard detection response times
- Efficient polling with change count detection
- Multi-level caching (memory and disk) via CacheManager

## Module Responsibilities

**ClipFlowCore**: Pure data models (ClipboardItem, ClipboardContent, Collection) with no dependencies

**ClipFlowAPI**: Protocol definitions and API contracts (ClipboardServiceAPI, HistoryFilter, TransformAction)

**ClipFlowBackend**: Business logic, database, monitoring, and service implementations

**ClipFlow**: UI layer, application lifecycle, manager coordination, and SwiftUI views

- never mention co-authored by claude or any mention of claude while commiting to github