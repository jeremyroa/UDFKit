import Foundation
import UDFKit

// MARK: - Benchmark infrastructure

struct BenchmarkResult {
    let label: String
    let totalMs: Int64
    let avgNs: Int64
    let iterations: Int
}

var outputLines: [String] = []

@MainActor func log(_ line: String = "") {
    print(line)
    outputLines.append(line)
}

@MainActor func writeResultsFile() {
    let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("benchmarks.txt")
    let content = outputLines.joined(separator: "\n") + "\n"
    try? content.write(to: path, atomically: true, encoding: .utf8)
}

@MainActor @discardableResult
func measure(
    _ label: String,
    iterations: Int = 1000,
    threshold avgNsLimit: Int64? = nil,
    _ work: @Sendable () async -> Void
) async -> BenchmarkResult {
    let clock = ContinuousClock()
    let elapsed = await clock.measure {
        for _ in 0 ..< iterations {
            await work()
        }
    }
    let totalMs = elapsed.components.attoseconds / 1_000_000_000_000_000
    let avgNs = elapsed.components.attoseconds / Int64(iterations) / 1_000_000_000
    let paddedLabel = label.padding(toLength: 64, withPad: " ", startingAt: 0)
    let status: String = if let limit = avgNsLimit {
        avgNs <= limit ? "✓" : "✗ OVER THRESHOLD (\(limit)ns)"
    } else {
        ""
    }
    log("\(paddedLabel)  \(totalMs)ms total  \(avgNs)ns avg  \(status)")
    return BenchmarkResult(label: label, totalMs: totalMs, avgNs: avgNs, iterations: iterations)
}

@MainActor @discardableResult
func measureSync(
    _ label: String,
    iterations: Int = 1000,
    _ work: () -> Void
) -> BenchmarkResult {
    let clock = ContinuousClock()
    let elapsed = clock.measure {
        for _ in 0 ..< iterations {
            work()
        }
    }
    let totalMs = elapsed.components.attoseconds / 1_000_000_000_000_000
    let avgNs = elapsed.components.attoseconds / Int64(iterations) / 1_000_000_000
    let paddedLabel = label.padding(toLength: 64, withPad: " ", startingAt: 0)
    log("\(paddedLabel)  \(totalMs)ms total  \(avgNs)ns avg")
    return BenchmarkResult(label: label, totalMs: totalMs, avgNs: avgNs, iterations: iterations)
}

// MARK: - Minimal Redux-style baseline (no UDFKit, pure Swift)

// Used as a lower-bound reference: raw function calls with no actor hops.

final class BaselineStore<State, Action> {
    private var state: State
    private let reducer: (inout State, Action) -> Void

    init(state: State, reducer: @escaping (inout State, Action) -> Void) {
        self.state = state
        self.reducer = reducer
    }

    func dispatch(_ action: Action) {
        reducer(&state, action)
    }
}

// MARK: - Shared benchmark state / actions / reducers

struct BenchState: StoreState {
    var count: Int = 0
    var text: String = ""
}

enum BenchAction: StoreAction {
    case increment
    case setText(String)
}

struct BenchReducer: Reducer {
    func reduce(oldState: BenchState, with action: BenchAction) -> BenchState {
        var state = oldState
        switch action {
        case .increment: state.count += 1
        case let .setText(text): state.text = text
        }
        return state
    }
}

struct NoOpEffect: Effect {
    func process(state: BenchState, with action: BenchAction) async -> BenchAction? {
        nil
    }
}

// MARK: - Thresholds

// Derived from baseline overhead + realistic headroom for actor hops on iPhone-class hardware.
// Raise a threshold only when you have profiler evidence that the cost is unavoidable.

private let singleDispatchThresholdNs: Int64 = 500_000 // 0.5 ms — single dispatch
private let builderDispatchThresholdNs: Int64 = 2_000_000 // 2 ms  — 50 sub-reducers
private let effectsDispatchThresholdNs: Int64 = 5_000_000 // 5 ms  — 50 no-op effects

// MARK: - Run

Task { @MainActor in
    log("UDFKit Benchmark Suite")
    log(String(repeating: "-", count: 80))

    // ── Baseline ────────────────────────────────────────────────────────────────
    // Pure-Swift, synchronous, no actor isolation. This is the theoretical floor.
    let baselineStore = BaselineStore<BenchState, BenchAction>(state: BenchState()) { state, action in
        switch action {
        case .increment: state.count += 1
        case let .setText(text): state.text = text
        }
    }
    let baseline = measureSync("Baseline — raw Swift reducer (no actors)", iterations: 10000) {
        baselineStore.dispatch(.increment)
    }

    log()
    log("── UDFKit ──────────────────────────────────────────────────────────────────")

    // 1. Single reducer — 10 000 sequential dispatches
    let store1 = Store(initialState: BenchState(), reducer: BenchReducer())
    let r1 = await measure(
        "Single reducer — 10 000 dispatches",
        iterations: 10000,
        threshold: singleDispatchThresholdNs
    ) {
        await store1.dispatch(.increment)
    }

    // 2. BuilderReducer with 1, 10, 50 sub-reducers — 1 000 dispatches each
    for count in [1, 10, 50] {
        var builder = BuilderReducer<BenchState, BenchAction>()
        for _ in 0 ..< count {
            builder = builder.registerReducer(\.self, BenchReducer())
        }
        let store = Store(initialState: BenchState(), reducer: builder)
        let limit: Int64 = count == 50 ? builderDispatchThresholdNs : singleDispatchThresholdNs
        await measure(
            "BuilderReducer \(count) sub-reducers — 1 000 dispatches",
            threshold: limit
        ) {
            await store.dispatch(.increment)
        }
    }

    // 3. BuilderEffects with 1, 10, 50 no-op effects — 1 000 dispatches each
    for count in [1, 10, 50] {
        let effects = BuilderEffects<BenchState, BenchAction>()
        for _ in 0 ..< count {
            effects.registerEffect(\.self, NoOpEffect())
        }
        try? await Task.sleep(for: .milliseconds(100))
        let store = Store(
            initialState: BenchState(),
            reducer: BenchReducer(),
            AnyEffect(effects)
        )
        let limit: Int64 = count == 50 ? effectsDispatchThresholdNs : singleDispatchThresholdNs
        await measure(
            "BuilderEffects \(count) no-op effects — 1 000 dispatches",
            threshold: limit
        ) {
            await store.dispatch(.increment)
        }
    }

    // 4. Store dispatch latency — 1 000 sequential dispatches
    let store4 = Store(initialState: BenchState(), reducer: BenchReducer())
    await measure(
        "Store dispatch latency — 1 000 sequential dispatches",
        threshold: singleDispatchThresholdNs
    ) {
        await store4.dispatch(.increment)
    }

    // 5. Concurrent dispatch — 100 tasks × 10 dispatches
    let store5 = Store(initialState: BenchState(), reducer: BenchReducer())
    let clock5 = ContinuousClock()
    let elapsed5 = await clock5.measure {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    for _ in 0 ..< 10 {
                        await store5.dispatch(.increment)
                    }
                }
            }
        }
    }
    let ms5 = elapsed5.components.attoseconds / 1_000_000_000_000_000
    let label5 = "Concurrent dispatch 100×10".padding(toLength: 64, withPad: " ", startingAt: 0)
    let concurrentThresholdMs: Int64 = 100
    let concurrentStatus = ms5 <= concurrentThresholdMs ? "✓" : "✗ OVER THRESHOLD (\(concurrentThresholdMs)ms)"
    log("\(label5)  \(ms5)ms total  final count=\(store5.state.count)  \(concurrentStatus)")

    // ── Overhead summary ────────────────────────────────────────────────────────
    log()
    log(String(repeating: "-", count: 80))
    let overheadNs = r1.avgNs - baseline.avgNs
    log(String(
        format: "Actor-hop overhead vs baseline: %+ldns avg per dispatch",
        overheadNs
    ))

    // ── Regression gate ─────────────────────────────────────────────────────────
    // Exit non-zero so CI fails fast on threshold violations.
    // Re-run with UDFKIT_BENCH_NO_GATE=1 to skip the gate during profiling.
    writeResultsFile()

    if ProcessInfo.processInfo.environment["UDFKIT_BENCH_NO_GATE"] == nil {
        let exceeded = r1.avgNs > singleDispatchThresholdNs
        if exceeded {
            fputs("REGRESSION: single-dispatch avg \(r1.avgNs)ns exceeds \(singleDispatchThresholdNs)ns threshold\n", stderr)
            exit(1)
        }
    }

    exit(0)
}

RunLoop.main.run()
