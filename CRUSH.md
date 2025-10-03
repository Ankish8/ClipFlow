# CRUSH.md

## Development Commands

### Build & Run
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

### Testing
No formal test suite exists. Manual testing involves:
1. Building and running the app
2. Testing clipboard monitoring
3. Verifying menu bar and overlay interfaces
4. Checking accessibility permissions flow

## Code Style Guidelines

### Architecture & Concurrency
- Layered architecture: ClipFlow (UI) → ClipFlowBackend (services) → ClipFlowAPI (protocols) → ClipFlowCore (models)
- Use @MainActor for all UI components and managers
- Swift 6 strict concurrency with DISABLE_SENDABLE_CHECKING migration flag
- Actor-based patterns for background operations, MainActor for UI

### Naming & Structure
- Manager classes for UI coordination (MenuBarManager, OverlayManager, AccessibilityManager)
- Service classes for business logic (ClipboardService, StorageService, CacheManager)
- Public struct models with Sendable conformance in ClipFlowCore
- MARK: comments for code organization
- Singleton pattern for shared managers (MenuBarManager.shared, OverlayManager.shared)

### Import Organization
1. System frameworks (Foundation, AppKit, SwiftUI)
2. External dependencies (Combine, KeyboardShortcuts, GRDB)
3. Internal modules (ClipFlowBackend, ClipFlowCore, ClipFlowAPI)
4. Local imports last

### Error Handling
- Use async/await with do-catch blocks
- Log errors with NSLog and print statements
- Graceful degradation for failed operations
- Maintain UI responsiveness during background operations

### SwiftUI & AppKit Integration
- SwiftUI views embedded in AppKit NSApplication
- Use NSStatusItem for menu bar integration
- KeyboardShortcuts library for global hotkeys (⌥⌘V)
- NSImage with SF Symbols for modern appearance

### File Organization
- Group by module and functionality
- Extensions in dedicated folders
- Views separated by feature (Cards/, Overlay/)
- Services separated by layer (Database/, Services/)