/**
 * MemoryOptimizationConfig - Memory optimization settings for Voxtral generation
 *
 * Inspired by flux-2-swift-mlx memory management patterns.
 * Provides presets for different RAM configurations and manual control.
 */

import Foundation
import MLX

/// Configuration for memory optimization during token generation
/// Based on flux-2-swift-mlx patterns for efficient GPU memory management
public struct MemoryOptimizationConfig: Sendable {

    /// Frequency of MLX eval() calls during generation (0 = disabled)
    /// Lower values = more frequent evaluation = lower memory but slower
    public var evalFrequency: Int

    /// Whether to clear GPU cache after each evaluation cycle
    public var clearCacheOnEval: Bool

    /// Whether to reset peak memory tracking periodically
    public var resetPeakMemory: Bool

    /// Maximum KV cache size (nil = unlimited)
    /// Set to limit memory for very long sequences
    public var maxKVCacheSize: Int?

    // MARK: - Presets

    /// Disabled - no memory optimization (fastest, highest memory)
    public static let disabled = MemoryOptimizationConfig(
        evalFrequency: 0,
        clearCacheOnEval: false,
        resetPeakMemory: false,
        maxKVCacheSize: nil
    )

    /// Moderate - balanced optimization (recommended for 32-64GB RAM)
    public static let moderate = MemoryOptimizationConfig(
        evalFrequency: 8,
        clearCacheOnEval: false,
        resetPeakMemory: true,
        maxKVCacheSize: nil
    )

    /// Aggressive - maximum memory savings (for <32GB RAM)
    public static let aggressive = MemoryOptimizationConfig(
        evalFrequency: 4,
        clearCacheOnEval: true,
        resetPeakMemory: true,
        maxKVCacheSize: 8192
    )

    /// Ultra - extreme memory savings (for 8-16GB RAM)
    public static let ultra = MemoryOptimizationConfig(
        evalFrequency: 2,
        clearCacheOnEval: true,
        resetPeakMemory: true,
        maxKVCacheSize: 4096
    )

    // MARK: - Auto-detection

    /// Automatically select configuration based on available RAM
    /// - Parameter ramGB: Available RAM in gigabytes (pass nil to auto-detect)
    /// - Returns: Recommended configuration for the system
    public static func recommended(forRAMGB ramGB: Int? = nil) -> MemoryOptimizationConfig {
        let ram = ramGB ?? Self.detectSystemRAM()

        switch ram {
        case 0..<16:
            return .ultra
        case 16..<32:
            return .aggressive
        case 32..<64:
            return .moderate
        default:
            return .disabled
        }
    }

    /// Detect system RAM in GB
    private static func detectSystemRAM() -> Int {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        return Int(physicalMemory / (1024 * 1024 * 1024))
    }

    // MARK: - Initialization

    public init(
        evalFrequency: Int = 0,
        clearCacheOnEval: Bool = false,
        resetPeakMemory: Bool = false,
        maxKVCacheSize: Int? = nil
    ) {
        self.evalFrequency = evalFrequency
        self.clearCacheOnEval = clearCacheOnEval
        self.resetPeakMemory = resetPeakMemory
        self.maxKVCacheSize = maxKVCacheSize
    }

    // MARK: - Description

    public var description: String {
        var parts: [String] = []
        parts.append("evalFreq=\(evalFrequency)")
        if clearCacheOnEval { parts.append("clearCache") }
        if resetPeakMemory { parts.append("resetPeak") }
        if let maxKV = maxKVCacheSize { parts.append("maxKV=\(maxKV)") }
        return "MemoryOptimizationConfig(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - MemoryOptimizationConfig + Equatable

extension MemoryOptimizationConfig: Equatable {
    public static func == (lhs: MemoryOptimizationConfig, rhs: MemoryOptimizationConfig) -> Bool {
        return lhs.evalFrequency == rhs.evalFrequency &&
               lhs.clearCacheOnEval == rhs.clearCacheOnEval &&
               lhs.resetPeakMemory == rhs.resetPeakMemory &&
               lhs.maxKVCacheSize == rhs.maxKVCacheSize
    }
}

// MARK: - MemoryOptimizationConfig + CustomStringConvertible

extension MemoryOptimizationConfig: CustomStringConvertible {}
