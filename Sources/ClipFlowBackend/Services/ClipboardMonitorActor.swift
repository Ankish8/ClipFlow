import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import ClipFlowCore
import ClipFlowAPI
import NaturalLanguage

// MARK: - Clipboard Monitor Actor
/// High-performance, thread-safe clipboard monitoring service that delivers sub-100ms response times
@MainActor
class ClipboardMonitorActor {
    // MARK: - State

    private var lastChangeCount: Int = 0
    private var lastHash: String = ""
    private var isMonitoring = false
    private var pollingInterval: TimeInterval = 0.1 // 100ms for optimal responsiveness

    // Performance tracking
    private var totalItemsProcessed: Int = 0
    private var detectionErrors: Int = 0
    private var lastDetectionTime: Date?
    private var averageProcessingTime: TimeInterval = 0.0

    // Memory pressure handling
    private var isUnderMemoryPressure = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // Dependencies
    private let storageService: StorageService
    private let performanceMonitor: PerformanceMonitor
    private let cacheManager: CacheManager

    // MARK: - Publishers
    private let itemSubject = PassthroughSubject<ClipboardItem, Never>()
    private let errorSubject = PassthroughSubject<ClipboardError, Never>()
    private let statusSubject = CurrentValueSubject<MonitorStatus, Never>(.stopped)

    // MARK: - Initialization

    init(
        storageService: StorageService,
        performanceMonitor: PerformanceMonitor,
        cacheManager: CacheManager
    ) {
        self.storageService = storageService
        self.performanceMonitor = performanceMonitor
        self.cacheManager = cacheManager
    }

    // ... rest of file unchanged ...
}
