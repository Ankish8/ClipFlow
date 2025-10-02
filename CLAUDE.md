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

### Development Build Flags
The project uses several Swift 6 compatibility flags in Package.swift:
- `-Xfrontend -disable-availability-checking` for development builds
- `-parse-as-library` for executable target configuration
- `DISABLE_SENDABLE_CHECKING` compilation flag for concurrency migration

### Testing
This project currently has no formal test suite. Testing is done manually by:
1. Building and running the application
2. Testing clipboard monitoring functionality
3. Verifying menu bar and overlay interfaces
4. Checking accessibility permissions flow

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

**Actor-Based Concurrency**: Uses @MainActor classes for UI components and data race prevention. The architecture transitions from actor-based monitoring to @MainActor class implementation for Swift 6 compatibility.

**Protocol-Oriented Design**: ClipboardServiceAPI defines the contract for clipboard operations, implemented by ClipboardService in the backend layer.

**Reactive Publishers**: Uses Combine framework with PassthroughSubject and CurrentValueSubject for real-time updates between clipboard monitoring and UI components.

**Menu Bar Application**: Runs as NSApplication.accessory (no dock icon) with:
- Menu bar status item for quick access
- Global hotkey overlay (⌥⌘V) via KeyboardShortcuts library
- SwiftUI views embedded in AppKit infrastructure

### Core Data Flow

1. **ClipboardMonitorService** polls NSPasteboard every 100ms using changeCount detection
2. **StorageService** persists items using GRDB.swift SQLite database with custom record mappings
3. **ClipboardService** coordinates between monitoring, storage, and UI layers
4. **MenuBarManager/OverlayManager** handle UI presentation and user interactions
5. **AccessibilityManager** manages macOS permissions for global hotkeys and system integration

### Critical Implementation Details

**Concurrency Model**: All UI managers are @MainActor isolated. Clipboard monitoring happens on background queues but publishes updates to MainActor for UI consumption. Swift 6 strict concurrency requires careful await/async patterns throughout.

**Application Lifecycle**: AppDelegate initializes services in sequence during `applicationDidFinishLaunching`:
- Core service initialization
- Permission checking and request flow
- Clipboard monitoring startup
- Cache warmup and performance monitoring

**Permission Requirements**: Requires accessibility permissions for:
- Global hotkey registration (⌥⌘V)
- Cross-application paste functionality
- Clipboard monitoring across all apps

**Database Schema**: Uses GRDB with DatabaseRecords.swift defining custom record types that map to/from domain models. The StorageService handles all database operations.

**Content Type System**: Polymorphic ClipboardContent enum in ClipFlowCore supports:
- Text (plain and rich)
- Images (with thumbnail generation)
- Files (from Finder drag operations)
- Links (with metadata extraction)
- Code snippets (with language detection)
- Colors (with hex conversion)
- Multi-content items

### Performance Architecture

**Caching Strategy**: Multi-level caching via CacheManager with memory and disk persistence. Cache warming occurs during app startup with configurable size limits.

**Monitoring Efficiency**: 100ms polling interval with NSPasteboard.changeCount optimization to avoid unnecessary processing.

**Memory Management**: ClipboardItem records are paginated and cached with automatic cleanup of old items.

### Security and Privacy

**V1 Simplified Security**: Security features were removed from v1 implementation to reduce complexity. SecurityMetadata struct exists but contains no active security enforcement.

**Privacy Compliance**: ClipboardMonitorService checks for concealed/transient pasteboard types to avoid capturing password manager data and other sensitive clipboard content.

## Important Constraints

### Swift 6 Concurrency
- Uses strict concurrency checking with DISABLE_SENDABLE_CHECKING flag for migration
- Requires careful @MainActor annotation for UI components
- All async operations must properly await on MainActor context
- Publisher chains must be properly isolated to prevent data races

### macOS Integration
- Minimum macOS 15 target (specified in Package.swift platforms)
- Uses AppKit for menu bar and accessibility features
- SwiftUI for modern UI components within AppKit NSApplication framework
- KeyboardShortcuts library for global hotkey support (⌥⌘V)

### Performance Requirements
- Sub-100ms clipboard detection response times
- Efficient polling with changeCount-based change detection
- Multi-level caching (memory and disk) via CacheManager
- Database operations must be non-blocking on main thread

## Module Responsibilities

**ClipFlowCore**: Pure data models (ClipboardItem, ClipboardContent, Collection, ItemMetadata) with no external dependencies. Contains all value types and enums.

**ClipFlowAPI**: Protocol definitions and API contracts (ClipboardServiceAPI, HistoryFilter, TransformAction). Defines the interface between backend services and UI layer.

**ClipFlowBackend**: Business logic, database operations, monitoring services, and cache management. Contains all service implementations and database schema.

**ClipFlow**: UI layer, application lifecycle, manager coordination, and SwiftUI views. Contains AppDelegate, view models, and all user interface components.

## Content Type Detection

Content detection occurs in ClipboardMonitorService using NSPasteboard type checking:
- String content becomes TextContent with metadata detection (email, phone, URL)
- NSImage data becomes ImageContent with dimension and format extraction
- File URLs become FileContent with size and type information
- Rich text preserves formatting through RichTextContent
- URL detection creates LinkContent with potential metadata fetching
- Code detection uses String+ContentDetection extensions for language identification

## Manager Coordination

The three main managers coordinate application behavior:
- **MenuBarManager**: Handles status item, popover presentation, and menu interactions
- **OverlayManager**: Manages global hotkey overlay window and keyboard shortcuts
- **AccessibilityManager**: Handles permission requests, status checking, and system integration