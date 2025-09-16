import Foundation
import os

// MARK: - Performance Monitor

public actor PerformanceMonitor {
    public static let shared = PerformanceMonitor()

    private var metrics: [String: [PerformanceMetric]] = [:]
    private var activeOperations: [String: Date] = [:]
    private let logger = Logger(subsystem: "com.clipflow.backend", category: "performance")

    // Configuration
    private let maxMetricsPerOperation = 1000
    private let alertThreshold: TimeInterval = 1.0 // 1 second
    private let memoryAlertThreshold: Int64 = 100 * 1024 * 1024 // 100MB

    private init() {
        startPeriodicReporting()
    }

    // MARK: - Measurement

    @discardableResult
    public func measure<T>(
        operation: String,
        category: String = "general",
        block: () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let memoryBefore = getCurrentMemoryUsage()

        activeOperations[operation] = Date()

        defer {
            activeOperations.removeValue(forKey: operation)
        }

        do {
            let result = try await block()

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let memoryAfter = getCurrentMemoryUsage()
            let memoryDelta = memoryAfter - memoryBefore

            await recordMetric(
                operation: operation,
                category: category,
                duration: duration,
                memoryUsage: memoryDelta,
                success: true
            )

            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let memoryAfter = getCurrentMemoryUsage()
            let memoryDelta = memoryAfter - memoryBefore

            await recordMetric(
                operation: operation,
                category: category,
                duration: duration,
                memoryUsage: memoryDelta,
                success: false,
                error: error
            )

            throw error
        }
    }

    public func startOperation(_ operation: String) async {
        activeOperations[operation] = Date()
    }

    public func endOperation(_ operation: String, success: Bool = true, error: Error? = nil) async {
        guard let startTime = activeOperations.removeValue(forKey: operation) else {
            logger.warning("Attempted to end operation '\(operation)' that wasn't started")
            return
        }

        let duration = Date().timeIntervalSince(startTime)
        let memoryUsage = getCurrentMemoryUsage()

        await recordMetric(
            operation: operation,
            category: "manual",
            duration: duration,
            memoryUsage: memoryUsage,
            success: success,
            error: error
        )
    }

    // MARK: - Metric Recording

    private func recordMetric(
        operation: String,
        category: String,
        duration: TimeInterval,
        memoryUsage: Int64,
        success: Bool,
        error: Error? = nil
    ) async {
        let metric = PerformanceMetric(
            operation: operation,
            category: category,
            duration: duration,
            memoryUsage: memoryUsage,
            timestamp: Date(),
            success: success,
            error: error?.localizedDescription
        )

        // Store metric
        if metrics[operation] == nil {
            metrics[operation] = []
        }

        metrics[operation]!.append(metric)

        // Limit metrics per operation
        if metrics[operation]!.count > maxMetricsPerOperation {
            metrics[operation]!.removeFirst(metrics[operation]!.count - maxMetricsPerOperation)
        }

        // Check for performance issues
        await checkPerformanceAlerts(metric: metric)

        // Log metric
        logger.debug("Operation '\(operation)' completed in \(duration * 1000, specifier: "%.1f")ms, memory: \(memoryUsage) bytes")
    }

    private func checkPerformanceAlerts(metric: PerformanceMetric) async {
        // Duration alert
        if metric.duration > alertThreshold {
            logger.warning("⚠️ Slow operation: '\(metric.operation)' took \(metric.duration * 1000, specifier: "%.1f")ms")
        }

        // Memory alert
        if metric.memoryUsage > memoryAlertThreshold {
            logger.warning("⚠️ High memory usage: '\(metric.operation)' used \(metric.memoryUsage / 1024 / 1024)MB")
        }

        // Error alert
        if !metric.success {
            logger.error("❌ Operation failed: '\(metric.operation)' - \(metric.error ?? "Unknown error")")
        }
    }

    // MARK: - Statistics

    public func getStatistics(for operation: String? = nil) async -> PerformanceStatistics {
        if let operation = operation {
            return calculateStatistics(for: operation)
        } else {
            return calculateOverallStatistics()
        }
    }

    private func calculateStatistics(for operation: String) -> PerformanceStatistics {
        guard let operationMetrics = metrics[operation] else {
            return PerformanceStatistics.empty(operation: operation)
        }

        let totalCount = operationMetrics.count
        let successCount = operationMetrics.filter { $0.success }.count
        let durations = operationMetrics.map { $0.duration }
        let memoryUsages = operationMetrics.map { $0.memoryUsage }

        return PerformanceStatistics(
            operation: operation,
            totalOperations: totalCount,
            successfulOperations: successCount,
            averageDuration: durations.reduce(0, +) / Double(totalCount),
            minDuration: durations.min() ?? 0,
            maxDuration: durations.max() ?? 0,
            p95Duration: percentile(durations, 0.95),
            p99Duration: percentile(durations, 0.99),
            averageMemoryUsage: memoryUsages.reduce(0, +) / Int64(totalCount),
            maxMemoryUsage: memoryUsages.max() ?? 0,
            errorRate: Double(totalCount - successCount) / Double(totalCount),
            firstRecorded: operationMetrics.first?.timestamp,
            lastRecorded: operationMetrics.last?.timestamp
        )
    }

    private func calculateOverallStatistics() -> PerformanceStatistics {
        let allMetrics = metrics.values.flatMap { $0 }

        guard !allMetrics.isEmpty else {
            return PerformanceStatistics.empty(operation: "overall")
        }

        let totalCount = allMetrics.count
        let successCount = allMetrics.filter { $0.success }.count
        let durations = allMetrics.map { $0.duration }
        let memoryUsages = allMetrics.map { $0.memoryUsage }

        return PerformanceStatistics(
            operation: "overall",
            totalOperations: totalCount,
            successfulOperations: successCount,
            averageDuration: durations.reduce(0, +) / Double(totalCount),
            minDuration: durations.min() ?? 0,
            maxDuration: durations.max() ?? 0,
            p95Duration: percentile(durations, 0.95),
            p99Duration: percentile(durations, 0.99),
            averageMemoryUsage: memoryUsages.reduce(0, +) / Int64(totalCount),
            maxMemoryUsage: memoryUsages.max() ?? 0,
            errorRate: Double(totalCount - successCount) / Double(totalCount),
            firstRecorded: allMetrics.first?.timestamp,
            lastRecorded: allMetrics.last?.timestamp
        )
    }

    // MARK: - Reporting

    public func getTopSlowOperations(limit: Int = 10) async -> [OperationSummary] {
        var summaries: [OperationSummary] = []

        for (operation, operationMetrics) in metrics {
            let avgDuration = operationMetrics.map { $0.duration }.reduce(0, +) / Double(operationMetrics.count)
            summaries.append(OperationSummary(
                operation: operation,
                averageDuration: avgDuration,
                totalOperations: operationMetrics.count
            ))
        }

        return summaries.sorted { $0.averageDuration > $1.averageDuration }.prefix(limit).map { $0 }
    }

    public func getActiveOperations() async -> [ActiveOperation] {
        return activeOperations.map { operation, startTime in
            ActiveOperation(
                operation: operation,
                startTime: startTime,
                duration: Date().timeIntervalSince(startTime)
            )
        }.sorted { $0.duration > $1.duration }
    }

    public func exportMetrics() async -> PerformanceReport {
        let statistics = await getStatistics()
        let topSlow = await getTopSlowOperations()
        let active = await getActiveOperations()

        return PerformanceReport(
            generatedAt: Date(),
            overallStatistics: statistics,
            operationStatistics: metrics.keys.map { calculateStatistics(for: $0) },
            topSlowOperations: topSlow,
            activeOperations: active,
            systemInfo: getSystemInfo()
        )
    }

    // MARK: - Maintenance

    public func clearMetrics(olderThan date: Date? = nil) async {
        if let date = date {
            for (operation, operationMetrics) in metrics {
                metrics[operation] = operationMetrics.filter { $0.timestamp > date }
            }
        } else {
            metrics.removeAll()
        }
    }

    public func getMemoryFootprint() async -> Int64 {
        let metricsCount = metrics.values.reduce(0) { $0 + $1.count }
        return Int64(metricsCount * MemoryLayout<PerformanceMetric>.size)
    }

    // MARK: - Private Helpers

    private func percentile(_ values: [TimeInterval], _ percentile: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * percentile)
        return sorted[min(index, sorted.count - 1)]
    }

    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func startPeriodicReporting() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000) // 5 minutes
                await logPeriodicSummary()
            }
        }
    }

    private func logPeriodicSummary() async {
        let stats = await getStatistics()
        let memoryFootprint = await getMemoryFootprint()

        logger.info("""
        📊 Performance Summary:
        Total Operations: \(stats.totalOperations)
        Average Duration: \(stats.averageDuration * 1000, specifier: "%.1f")ms
        Success Rate: \(stats.successRate * 100, specifier: "%.1f")%
        Memory Footprint: \(memoryFootprint / 1024)KB
        """)
    }

    private func getSystemInfo() -> SystemInfo {
        var systemInfo = utsname()
        uname(&systemInfo)

        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let machine = machineMirror.children.reduce("") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return result }
            return result + String(UnicodeScalar(UInt8(value))!)
        }

        return SystemInfo(
            machine: machine,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            processorCount: ProcessInfo.processInfo.processorCount,
            physicalMemory: Int64(ProcessInfo.processInfo.physicalMemory)
        )
    }
}

// MARK: - Supporting Types

public struct PerformanceMetric {
    public let operation: String
    public let category: String
    public let duration: TimeInterval
    public let memoryUsage: Int64
    public let timestamp: Date
    public let success: Bool
    public let error: String?

    public init(
        operation: String,
        category: String,
        duration: TimeInterval,
        memoryUsage: Int64,
        timestamp: Date,
        success: Bool,
        error: String? = nil
    ) {
        self.operation = operation
        self.category = category
        self.duration = duration
        self.memoryUsage = memoryUsage
        self.timestamp = timestamp
        self.success = success
        self.error = error
    }
}

public struct PerformanceStatistics {
    public let operation: String
    public let totalOperations: Int
    public let successfulOperations: Int
    public let averageDuration: TimeInterval
    public let minDuration: TimeInterval
    public let maxDuration: TimeInterval
    public let p95Duration: TimeInterval
    public let p99Duration: TimeInterval
    public let averageMemoryUsage: Int64
    public let maxMemoryUsage: Int64
    public let errorRate: Double
    public let firstRecorded: Date?
    public let lastRecorded: Date?

    public var successRate: Double {
        totalOperations > 0 ? Double(successfulOperations) / Double(totalOperations) : 0
    }

    static func empty(operation: String) -> PerformanceStatistics {
        PerformanceStatistics(
            operation: operation,
            totalOperations: 0,
            successfulOperations: 0,
            averageDuration: 0,
            minDuration: 0,
            maxDuration: 0,
            p95Duration: 0,
            p99Duration: 0,
            averageMemoryUsage: 0,
            maxMemoryUsage: 0,
            errorRate: 0,
            firstRecorded: nil,
            lastRecorded: nil
        )
    }
}

public struct OperationSummary {
    public let operation: String
    public let averageDuration: TimeInterval
    public let totalOperations: Int
}

public struct ActiveOperation {
    public let operation: String
    public let startTime: Date
    public let duration: TimeInterval
}

public struct PerformanceReport {
    public let generatedAt: Date
    public let overallStatistics: PerformanceStatistics
    public let operationStatistics: [PerformanceStatistics]
    public let topSlowOperations: [OperationSummary]
    public let activeOperations: [ActiveOperation]
    public let systemInfo: SystemInfo
}

public struct SystemInfo {
    public let machine: String
    public let systemVersion: String
    public let processorCount: Int
    public let physicalMemory: Int64
}