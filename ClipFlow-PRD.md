# ClipFlow - Product Requirements Document (PRD)

## Document Status
- **Version**: 1.0
- **Last Updated**: September 16, 2025
- **Status**: Implementation In Progress
- **Next Review**: TBD

## 1. Product Overview

### 1.1 Product Vision
ClipFlow is a macOS clipboard manager that provides seamless clipboard history tracking and management. The application aims to enhance productivity by allowing users to access, search, and manage their clipboard history with an intuitive interface.

### 1.2 Target Platform
- **Primary Platform**: macOS 15.4+ (Sequoia)
- **Technology Stack**: Swift 6.2, SwiftUI, NSPasteboard API
- **Architecture**: Swift Package Manager multi-module design

### 1.3 User Persona
- **Primary Users**: macOS power users, developers, content creators
- **Use Cases**: Managing multiple clipboard items, accessing clipboard history, organizing copied content

## 2. Current Implementation Status

### 2.1 ✅ IMPLEMENTED FEATURES

#### Core Clipboard Monitoring
- **Status**: ✅ Working
- **Implementation**: Direct NSPasteboard polling (1-second interval)
- **Supported Content Types**:
  - ✅ Plain Text
  - ✅ Rich Text (RTF with formatting)
  - ✅ Images (PNG, TIFF)
  - ✅ Files (URLs from Finder)
  - ✅ Web URLs
- **Change Detection**: Based on NSPasteboard.changeCount

#### User Interface
- **Status**: ✅ Working
- **Framework**: SwiftUI
- **Layout**: HSplitView with sidebar and detail view
- **Components**:
  - ✅ Search bar
  - ✅ Clipboard items list
  - ✅ Detail view for selected items
  - ✅ Empty state handling

#### Application Lifecycle
- **Status**: ✅ Working
- **Features**:
  - ✅ Window activation on launch
  - ✅ Proper app delegate setup
  - ✅ Debug logging for troubleshooting

#### Content Processing
- **Status**: ✅ Working
- **Features**:
  - ✅ Priority-based content type detection
  - ✅ Content deduplication by hash
  - ✅ Metadata generation
  - ✅ Memory management (100-item limit in simple mode)

### 2.2 🏗️ PARTIALLY IMPLEMENTED FEATURES

#### Advanced Service Architecture
- **Status**: 🏗️ Built but not active
- **Components Available**:
  - ClipboardService with complex monitoring
  - StorageService with SQLite + GRDB
  - SecurityService with encryption
  - CacheManager with LRU eviction
  - PerformanceMonitor
- **Issue**: Service initialization chain has dependency/timing issues
- **Current Workaround**: Simple polling implementation bypasses this

#### Data Models
- **Status**: 🏗️ Complete but underutilized
- **Available**: Comprehensive ClipboardItem, ClipboardContent models
- **Usage**: Simple implementation uses basic model subset

### 2.3 ❌ NOT YET IMPLEMENTED

#### User Actions
- ❌ Pin/Unpin items
- ❌ Mark as favorite
- ❌ Delete items
- ❌ Paste with transformations
- ❌ Tag management

#### Search & Filtering
- ❌ Full-text search (FTS5)
- ❌ Advanced filtering
- ❌ Search by application source

#### Data Persistence
- ❌ SQLite database storage
- ❌ Data survival between app restarts
- ❌ Large content disk storage

#### Advanced Features
- ❌ Keyboard shortcuts
- ❌ Content encryption
- ❌ Privacy compliance features
- ❌ Performance monitoring UI
- ❌ Settings/preferences

## 3. Technical Architecture

### 3.1 Current Working Architecture
```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
│    ContentView, SearchBar, ItemsList    │
└─────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────┐
│           ClipboardViewModel            │
│    Simple Timer-based NSPasteboard     │
│         Polling (1sec interval)         │
└─────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────┐
│            Core Data Models             │
│   ClipboardItem, ClipboardContent       │
└─────────────────────────────────────────┘
```

### 3.2 Planned Architecture (Available but Inactive)
```
┌─────────────────────────────────────────┐
│              SwiftUI Views              │
└─────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────┐
│           ClipboardViewModel            │
│      (Reactive Service Integration)     │
└─────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────┐
│            Service Layer                │
│  ClipboardService, StorageService       │
│  SecurityService, CacheManager          │
└─────────────────────────────────────────┘
                     │
┌─────────────────────────────────────────┐
│            Data Layer                   │
│   DatabaseManager, FileStorage          │
└─────────────────────────────────────────┘
```

## 4. Feature Requirements

### 4.1 HIGH PRIORITY (P0) - Core Functionality

#### Reliable Clipboard Monitoring
- **Requirement**: Detect all clipboard changes reliably
- **Current Status**: ✅ Working with 1-second polling
- **Acceptance Criteria**:
  - ✅ Detect text changes
  - ✅ Detect image changes
  - ✅ Detect file changes
  - ✅ No duplicate entries

#### Multi-Content Type Support
- **Requirement**: Support all major clipboard content types
- **Current Status**: ✅ Working
- **Acceptance Criteria**:
  - ✅ Plain text processing
  - ✅ Rich text with formatting
  - ✅ Images (PNG, TIFF)
  - ✅ File URLs
  - ✅ Web URLs

#### Basic User Interface
- **Requirement**: Functional UI for viewing clipboard history
- **Current Status**: ✅ Working
- **Acceptance Criteria**:
  - ✅ List of clipboard items
  - ✅ Detail view for selected items
  - ✅ Search functionality (in-memory)
  - ✅ Responsive layout

### 4.2 MEDIUM PRIORITY (P1) - Enhanced Functionality

#### Data Persistence
- **Requirement**: Clipboard history survives app restarts
- **Current Status**: ❌ Not implemented
- **Dependencies**: Activate existing StorageService
- **Acceptance Criteria**:
  - Clipboard history loads on app start
  - Data persists between sessions
  - Configurable history limits

#### User Actions
- **Requirement**: Basic clipboard item management
- **Current Status**: ❌ UI exists but actions not connected
- **Dependencies**: Service layer activation
- **Acceptance Criteria**:
  - Pin/unpin important items
  - Delete unwanted items
  - Mark items as favorites
  - Copy items back to clipboard

#### Search & Filtering
- **Requirement**: Advanced search capabilities
- **Current Status**: ❌ Only basic in-memory filtering
- **Dependencies**: Database with FTS5
- **Acceptance Criteria**:
  - Full-text search across all content
  - Filter by content type
  - Filter by source application
  - Search performance < 100ms

### 4.3 LOW PRIORITY (P2) - Advanced Features

#### Keyboard Shortcuts
- **Requirement**: Global hotkeys for quick access
- **Current Status**: ❌ Framework included but not implemented
- **Dependencies**: KeyboardShortcuts integration
- **Acceptance Criteria**:
  - Configurable global shortcuts
  - Quick clipboard access without UI
  - Paste with position selection

#### Content Transformations
- **Requirement**: Transform content before pasting
- **Current Status**: ❌ Models exist but not implemented
- **Dependencies**: Service layer activation
- **Acceptance Criteria**:
  - Text transformations (case, formatting)
  - Content extraction (URLs, emails)
  - Format conversions

#### Privacy & Security
- **Requirement**: Secure handling of sensitive content
- **Current Status**: ❌ SecurityService exists but inactive
- **Dependencies**: Service architecture activation
- **Acceptance Criteria**:
  - Automatic sensitive content detection
  - Optional encryption for sensitive items
  - Configurable data retention policies

## 5. Success Metrics

### 5.1 Performance Metrics
- **Clipboard Detection Latency**: < 2 seconds (Currently ~1 second)
- **UI Responsiveness**: < 100ms for list updates
- **Memory Usage**: < 50MB for 1000 items
- **Search Performance**: < 100ms (when implemented)

### 5.2 Functionality Metrics
- **Content Type Coverage**: 5/5 major types supported ✅
- **Feature Completeness**: 30% (core monitoring working)
- **Data Persistence**: 0% (not implemented)
- **User Actions**: 0% (not connected)

### 5.3 Quality Metrics
- **Crash Rate**: 0% (no crashes observed)
- **Data Loss Rate**: 100% (no persistence)
- **User Experience**: Basic but functional

## 6. Dependencies & Risks

### 6.1 Technical Dependencies
- **macOS Sequoia**: Required for target platform
- **NSPasteboard API**: Core dependency for clipboard access
- **GRDB.swift**: Database layer (available but not active)
- **SwiftUI**: UI framework

### 6.2 Current Risks

#### Service Architecture Risk - HIGH
- **Issue**: Complex service initialization chain not working
- **Impact**: Advanced features unavailable
- **Mitigation**: Current simple polling approach provides basic functionality
- **Resolution Path**: Debug service dependencies and initialization order

#### Data Loss Risk - HIGH
- **Issue**: No data persistence implemented
- **Impact**: All clipboard history lost on app restart
- **Mitigation**: Current session maintains history
- **Resolution Path**: Activate StorageService with database

#### Performance Risk - MEDIUM
- **Issue**: 1-second polling may be too slow for some users
- **Impact**: Slight delay in clipboard detection
- **Mitigation**: Consistent behavior, no missed changes
- **Resolution Path**: Optimize polling interval or fix reactive monitoring

### 6.3 External Dependencies
- **macOS Privacy Settings**: User must grant clipboard access
- **System Performance**: Polling frequency limited by system impact
- **Third-party Apps**: Clipboard content depends on source applications

## 7. Development Roadmap

### 7.1 Phase 1: Fix Core Architecture (Current Priority)
- **Goal**: Activate existing service layer
- **Tasks**:
  - Debug service initialization issues
  - Fix dependency injection chain
  - Test reactive clipboard monitoring
  - Validate database storage
- **Success Criteria**: Service-based monitoring works reliably

### 7.2 Phase 2: Data Persistence
- **Goal**: Implement reliable data storage
- **Dependencies**: Phase 1 completion
- **Tasks**:
  - Activate StorageService integration
  - Implement data migration
  - Add configurable retention policies
  - Test persistence across app restarts

### 7.3 Phase 3: User Actions & Search
- **Goal**: Complete core user functionality
- **Dependencies**: Phase 1-2 completion
- **Tasks**:
  - Connect UI actions to services
  - Implement full-text search
  - Add filtering capabilities
  - Optimize search performance

### 7.4 Phase 4: Advanced Features
- **Goal**: Professional-grade functionality
- **Dependencies**: Phase 1-3 completion
- **Tasks**:
  - Keyboard shortcuts
  - Content transformations
  - Security features
  - Performance monitoring UI

## 8. Open Questions & Decisions Needed

### 8.1 Technical Decisions
1. **Service Architecture**: Should we debug the complex service layer or evolve the simple approach?
2. **Polling Frequency**: Is 1-second polling acceptable or should we optimize for faster detection?
3. **Data Storage**: How much clipboard history should we store by default?
4. **Performance vs Features**: Should we prioritize reliability or feature completeness?

### 8.2 Product Decisions
1. **Target Users**: Focus on power users or broader consumer market?
2. **Feature Scope**: MVP vs comprehensive clipboard manager?
3. **Privacy Approach**: Opt-in security features or privacy-first by default?
4. **Distribution**: Mac App Store vs direct distribution?

## 9. Conclusion

ClipFlow currently has a **working core** with basic clipboard monitoring and multi-content type support. The foundation is solid with a **comprehensive but inactive service architecture** ready for activation.

**Immediate Priority**: Debug and activate the existing service layer to unlock persistence, search, and user actions. The simple polling approach proves the concept works - now we need to make it production-ready.

**Success Definition**: A reliable, fast clipboard manager that enhances productivity without getting in the user's way.