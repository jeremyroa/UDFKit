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
    var counter: CounterState = .init()
    var profile: ProfileState = .init()
    var search: SearchState  = .init()
}

struct CounterState: StoreState { var count: Int = 0 }
struct ProfileState: StoreState { var name: String = "" }
struct SearchState:  StoreState { var query: String = "" }

enum BenchAction: StoreAction {
    case counter(CounterAction)
    case profile(ProfileAction)
    case search(SearchAction)
}

enum CounterAction: StoreAction { case increment }
enum ProfileAction: StoreAction { case setName(String) }
enum SearchAction:  StoreAction { case setQuery(String) }

struct CounterReducer: Reducer {
    func reduce(oldState: CounterState, with action: CounterAction) -> CounterState {
        var state = oldState
        switch action {
        case .increment: state.count += 1
        }
        return state
    }
}

struct ProfileReducer: Reducer {
    func reduce(oldState: ProfileState, with action: ProfileAction) -> ProfileState {
        var state = oldState
        switch action {
        case let .setName(name): state.name = name
        }
        return state
    }
}

struct SearchReducer: Reducer {
    func reduce(oldState: SearchState, with action: SearchAction) -> SearchState {
        var state = oldState
        switch action {
        case let .setQuery(query): state.query = query
        }
        return state
    }
}

// BenchReducer — opera sobre BenchState con BenchAction
// Necesario para stores de latencia y concurrencia (mismo State y Action que storeDSL)
struct BenchReducer: Reducer {
    func reduce(oldState: BenchState, with action: BenchAction) -> BenchState {
        var state = oldState
        switch action {
        case .counter(.increment):
            state.counter.count += 1
        case .profile(let a):
            switch a { case let .setName(n): state.profile.name = n }
        case .search(let a):
            switch a { case let .setQuery(q): state.search.query = q }
        }
        return state
    }
}

struct CounterEffect: Effect {
    func process(state: CounterState, with action: CounterAction) async -> CounterAction? { nil }
}

struct ProfileEffect: Effect {
    func process(state: ProfileState, with action: ProfileAction) async -> ProfileAction? { nil }
}

struct SearchEffect: Effect {
    func process(state: SearchState, with action: SearchAction) async -> SearchAction? { nil }
}

// MARK: - Thresholds

private let singleDispatchThresholdNs: Int64  = 500_000
private let dslDispatchThresholdNs: Int64     = 2_000_000
private let effectsDispatchThresholdNs: Int64 = 5_000_000

// MARK: - Run

Task { @MainActor in
    log("UDFKit Benchmark Suite")
    log(String(repeating: "-", count: 80))

    // ── Baseline ────────────────────────────────────────────────────────────────
    let baselineStore = BaselineStore<CounterState, CounterAction>(state: CounterState()) { state, action in
        switch action {
        case .increment: state.count += 1
        }
    }
    let baseline = measureSync("Baseline — raw Swift reducer (no actors)", iterations: 10000) {
        baselineStore.dispatch(.increment)
    }

    log()
    log("── UDFKit ──────────────────────────────────────────────────────────────────")

    // 1. Single reducer — 10 000 sequential dispatches
    let store1 = Store<BenchState, BenchAction>(state: .init()) {
        ReducerScope(\.counter, CounterReducer())
    }
    let r1 = await measure(
        "Single reducer — 10 000 dispatches",
        iterations: 10000,
        threshold: singleDispatchThresholdNs
    ) {
        await store1.dispatch(.counter(.increment))
    }

    // 2. DSL — Store con 3 ReducerScope + 3 EffectScope
    let storeDSL = Store<BenchState, BenchAction>(state: .init()) {
        ReducerScope(\.counter, CounterReducer())
        ReducerScope(\.profile, ProfileReducer())
        ReducerScope(\.search,  SearchReducer())
    } effects: {
        EffectScope(\.counter, CounterEffect())
        EffectScope(\.profile, ProfileEffect())
        EffectScope(\.search,  SearchEffect())
    }

    await measure(
        "DSL Store — 3 reducers + 3 effects — 1 000 dispatches",
        threshold: dslDispatchThresholdNs
    ) {
        await storeDSL.dispatch(.counter(.increment))
    }

    await measure(
        "DSL Store — effects dispatch — 1 000 dispatches",
        threshold: effectsDispatchThresholdNs
    ) {
        await storeDSL.dispatch(.search(.setQuery("bench")))
    }

    // 3. Store dispatch latency — 1 000 sequential dispatches
    let store3 = Store<BenchState, BenchAction>(
        state: BenchState()) {
            ReducerScope(\.counter, CounterReducer())
        }
    await measure(
        "Store dispatch latency — 1 000 sequential dispatches",
        threshold: singleDispatchThresholdNs
    ) {
        await store3.dispatch(.counter(.increment))
    }

    // 4. Concurrent dispatch — 100 tasks × 10 dispatches
    let store4 = Store<BenchState, BenchAction>(
        state: BenchState()) {
            ReducerScope(\.counter, CounterReducer())
        }
    let clock4 = ContinuousClock()
    let elapsed4 = await clock4.measure {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    for _ in 0 ..< 10 {
                        await store4.dispatch(.counter(.increment))
                    }
                }
            }
        }
    }
    let ms4 = elapsed4.components.attoseconds / 1_000_000_000_000_000
    let label4 = "Concurrent dispatch 100×10".padding(toLength: 64, withPad: " ", startingAt: 0)
    let concurrentThresholdMs: Int64 = 100
    let concurrentStatus = ms4 <= concurrentThresholdMs ? "✓" : "✗ OVER THRESHOLD (\(concurrentThresholdMs)ms)"
    log("\(label4)  \(ms4)ms total  final count=\(store4.state.counter.count)  \(concurrentStatus)")

    // ── Overhead summary ────────────────────────────────────────────────────────
    log()
    log(String(repeating: "-", count: 80))
    let overheadNs = r1.avgNs - baseline.avgNs
    log(String(
        format: "Actor-hop overhead vs baseline: %+ldns avg per dispatch",
        overheadNs
    ))

    // ── Regression gate ─────────────────────────────────────────────────────────
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
