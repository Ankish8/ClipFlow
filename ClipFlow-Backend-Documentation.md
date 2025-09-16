# ClipFlow Backend Architecture Documentation

## Overview

ClipFlow backend is a comprehensive macOS clipboard management system built with Swift 6.2, optimized for macOS Sequoia (15.4+). The backend provides complete feature parity with Paste app while maintaining superior performance and security.

## Architecture Overview

### 🏗️ Clean Architecture Pattern
```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                       │
│                    (Future Frontend)                        │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                      API Layer                              │
│    ClipboardServiceAPI, CollectionServiceAPI, etc.         │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                   Service Layer                             │
│  ClipboardService, StorageService, SecurityService         │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                   Domain Layer                              │
│     ClipboardItem, Collection, Business Logic              │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                   Data Layer                                │
│    DatabaseManager, CacheManager, FileStorage              │
└─────────────────────────────────────────────────────────────┘
```

### 🎯 Key Design Principles

1. **Actor-Based Concurrency**: Thread-safe operations using Swift actors
2. **Protocol-Oriented Design**: Easy testing and dependency injection
3. **Performance First**: Sub-100ms response times for all operations
4. **Security by Design**: AES-256 encryption and privacy compliance
5. **Reactive Architecture**: Combine publishers for real-time updates

## 📂 Project Structure

```
ClipFlowBackend/
├── Sources/
│   ├── ClipFlowCore/           # Core data models and types
│   │   └── Models/
│   │       ├── ClipboardItem.swift
│   │       ├── ItemMetadata.swift
│   │       └── Collection.swift
│   ├── ClipFlowAPI/            # API protocols and interfaces
│   │   └── ClipboardServiceAPI.swift
│   └── ClipFlowBackend/        # Implementation
│       ├── Database/
│       │   ├── DatabaseManager.swift
│       │   └── DatabaseRecords.swift
│       └── Services/
│           ├── ClipboardService.swift
│           ├── ClipboardMonitorService.swift
│           ├── StorageService.swift
│           ├── CacheManager.swift
│           ├── SecurityService.swift
│           └── PerformanceMonitor.swift
├── Package.swift
└── Tests/
```

## 🚀 Core Services

### ClipboardMonitorService

**Purpose**: Monitors macOS clipboard changes with privacy compliance

**Key Features**:
- 150ms polling interval for responsive detection
- macOS Sequoia privacy compliance (`NSPasteboard.canReadObject`)
- Automatic content type detection (text, images, files, colors)
- Smart duplicate detection using SHA256 hashes
- Reactive updates via Combine publishers

**Usage**:
```swift
let monitor = ClipboardMonitorService(...)
await monitor.startMonitoring()

monitor.itemUpdates
    .sink { item in
        print("New clipboard item: \(item.content.displayText)")
    }
    .store(in: &cancellables)
```

### StorageService

**Purpose**: High-performance data persistence with intelligent caching

**Key Features**:
- SQLite with FTS5 full-text search (sub-100ms search)
- LRU cache with 50MB memory limit
- Large content (>1MB) stored separately on disk
- Automatic data compression and cleanup
- Performance metrics tracking

**Architecture**:
```swift
// Three-tier storage system
Memory Cache (50MB) → SQLite Database → Disk Storage (large files)
```

### SecurityService

**Purpose**: Enterprise-grade security and privacy protection

**Key Features**:
- AES-256-GCM encryption for sensitive content
- Keychain integration with biometric authentication
- Automatic sensitive content detection
- Privacy-compliant data handling
- Configurable retention policies

**Security Layers**:
```swift
// Content analysis → Encryption → Secure storage → Access control
```

### CacheManager

**Purpose**: Intelligent memory management with LRU eviction

**Key Features**:
- 50MB memory limit with automatic eviction
- LRU (Least Recently Used) strategy
- 5-minute TTL for cached items
- Preloading of pinned/favorite items
- Real-time hit rate monitoring

### PerformanceMonitor

**Purpose**: Comprehensive performance tracking and optimization

**Key Features**:
- Sub-millisecond operation timing
- Memory usage tracking
- Automatic performance alerts
- P95/P99 latency metrics
- System resource monitoring

## 📊 Data Models

### ClipboardItem
The core model representing any clipboard content:

```swift
struct ClipboardItem {
    let id: UUID
    let content: ClipboardContent        // The actual content
    let metadata: ItemMetadata           // Size, hash, preview
    let source: ItemSource               // Application info
    let timestamps: ItemTimestamps       // Created, accessed, expires
    let security: SecurityMetadata       // Encryption status
    var tags: Set<String>               // User tags
    var collectionIds: Set<UUID>        // Collection membership
    var isFavorite: Bool
    var isPinned: Bool
    var isDeleted: Bool
}
```

### Content Types
Supports all major clipboard content types:

```swift
enum ClipboardContent {
    case text(TextContent)              // Plain text with language detection
    case richText(RichTextContent)      // RTF, HTML, attributed strings
    case image(ImageContent)            // PNG, JPEG, with thumbnails
    case file(FileContent)              // File URLs and metadata
    case link(LinkContent)              // URLs with metadata
    case code(CodeContent)              // Code with syntax highlighting
    case color(ColorContent)            // Color values
    case snippet(SnippetContent)        // Reusable snippets
    case multiple(MultiContent)         // Multiple items
}
```

## 🔍 Search & Indexing

### FTS5 Full-Text Search
```sql
-- Virtual table for blazing-fast search
CREATE VIRTUAL TABLE items_fts USING fts5(
    content_text,
    tags,
    application_name,
    tokenize='porter unicode61'
);
```

### Search Performance
- **Sub-100ms** response times for 10,000+ items
- **Porter stemming** for improved text matching
- **Incremental indexing** as content is added
- **Application context** tracking for refined searches

## 🔒 Security Architecture

### Encryption Pipeline
```swift
// 1. Content Analysis
let isSensitive = SecurityMetadata.detectSensitive(from: content)

// 2. Key Management
let key = try await getOrCreateEncryptionKey() // AES-256

// 3. Encryption
let encrypted = try AES.GCM.seal(data, using: key)

// 4. Secure Storage
try await keychain.store(keyData, requireBiometric: true)
```

### Privacy Compliance
- **macOS Sequoia** compatibility with new pasteboard privacy
- **Concealed content** detection (password managers)
- **Transient content** handling
- **Sensitive pattern** recognition (passwords, API keys, credit cards)

## 📈 Performance Metrics

### Target Performance
- **< 10MB** memory usage for basic operation
- **< 200ms** application startup time
- **< 100ms** search response across 10,000+ items
- **150ms** clipboard polling without CPU impact
- **Sub-100ms** cache retrieval times

### Monitoring
```swift
let stats = await performanceMonitor.getStatistics()
print("Average operation time: \(stats.averageDuration * 1000)ms")
print("Cache hit rate: \(stats.cacheStats.hitRate * 100)%")
```

## 🔄 Reactive Architecture

### Publisher Pattern
All services expose Combine publishers for reactive UI updates:

```swift
// Real-time clipboard updates
service.itemUpdates
    .receive(on: DispatchQueue.main)
    .sink { item in
        // Update UI with new item
    }
    .store(in: &cancellables)

// Error handling
service.errors
    .sink { error in
        // Handle clipboard errors
    }
    .store(in: &cancellables)

// Status monitoring
service.statusUpdates
    .sink { status in
        // Update monitoring status UI
    }
    .store(in: &cancellables)
```

## 🛠️ API Usage Examples

### Basic Clipboard Operations
```swift
// Start monitoring
try await clipboardService.startMonitoring()

// Get current clipboard
let currentItem = await clipboardService.getCurrentClipboard()

// Search clipboard history
let results = try await clipboardService.search(
    query: "password",
    scope: .content,
    limit: 50
)

// Write to clipboard
try await clipboardService.writeToClipboard(item)
```

### Advanced Features
```swift
// Pin important items
try await clipboardService.togglePin(itemId: item.id)

// Add tags for organization
try await clipboardService.addTags(["work", "important"], to: item.id)

// Transform content before pasting
try await clipboardService.paste(item, transform: .toUpperCase)
```

### Content Transformation
```swift
// Available transformations
enum TransformAction {
    case toUpperCase, toLowerCase
    case removeFormatting
    case extractURLs, extractEmails
    case base64Encode, base64Decode
    case jsonFormat, xmlFormat
    case trimWhitespace
}
```

## 📱 Integration Patterns

### Dependency Injection
```swift
// Services are designed for easy testing
class ClipboardService {
    init(
        storageService: StorageService,
        securityService: SecurityService,
        performanceMonitor: PerformanceMonitor
    ) {
        // Dependencies injected for testability
    }
}
```

### Protocol-Based Design
```swift
// Easy to mock for testing
protocol ClipboardServiceAPI {
    func startMonitoring() async throws
    func getHistory(...) async throws -> [ClipboardItem]
    // ... all operations as protocols
}
```

## 🧪 Testing Strategy

### Unit Testing
- Mock implementations of all protocols
- Performance benchmarks for critical paths
- Security testing for encryption/decryption
- Database migration testing

### Integration Testing
- End-to-end clipboard monitoring
- Search performance testing
- Cache behavior validation
- Error handling scenarios

## 🚀 Performance Optimizations

### Database Optimizations
```sql
-- Strategic indexes for common queries
CREATE INDEX idx_items_created ON clipboard_items(created_at DESC);
CREATE INDEX idx_items_pinned ON clipboard_items(is_pinned, created_at DESC);
CREATE INDEX idx_items_hash ON clipboard_items(hash);
```

### Memory Management
- **Autoreleasepool** blocks for image processing
- **LRU eviction** prevents memory bloat
- **Lazy loading** of large content from disk
- **Weak references** to prevent retain cycles

### Async/Await Patterns
- Non-blocking database operations
- Concurrent content processing
- Efficient resource utilization

## 🔧 Configuration

### Database Configuration
```swift
// Configurable storage limits
maxMemoryBytes: 50 * 1024 * 1024    // 50MB cache
maxItems: 1000                       // Item limit
pollingInterval: 0.15               // 150ms monitoring
```

### Security Configuration
```swift
// Flexible security policies
SecurityPolicy(
    encryptSensitiveContent: true,
    encryptAllContent: false,
    sensitiveRetentionDays: 7,
    regularRetentionDays: 30
)
```

## 🎯 Future Enhancements

### Planned Features
1. **XPC Service** implementation for privileged background operations
2. **iCloud Sync** for cross-device clipboard sharing
3. **Machine Learning** content categorization
4. **Advanced Automation** rules and workflows
5. **Plugin Architecture** for extensibility

### Performance Improvements
- **Vector Search** for semantic similarity
- **Compressed Storage** for large content
- **Background Indexing** for better search
- **Smart Prefetching** based on usage patterns

## 📚 Dependencies

### Core Dependencies
- **GRDB.swift** (6.0+): SQLite wrapper with Swift integration
- **CryptoKit**: Native encryption support
- **Combine**: Reactive programming
- **SwiftUI**: Future UI integration

### Optional Dependencies
- **KeyboardShortcuts**: Global hotkey support (future)
- **Sparkle**: Auto-update framework (future)

## 🔍 Debugging & Monitoring

### Performance Monitoring
```swift
// Built-in performance tracking
let report = await performanceMonitor.exportMetrics()
print("Total operations: \(report.overallStatistics.totalOperations)")
print("Average duration: \(report.overallStatistics.averageDuration)ms")
```

### Logging
```swift
// Structured logging with os.Logger
private let logger = Logger(subsystem: "com.clipflow.backend", category: "clipboard")
logger.debug("Clipboard item processed successfully")
logger.warning("Slow operation detected: \(operation)")
```

This backend architecture provides a solid foundation for a professional-grade clipboard manager that rivals commercial solutions while maintaining extensibility for future enhancements.
